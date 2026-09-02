package com.evervault.googlepay

import android.content.Context
import android.util.Log
import com.google.android.gms.wallet.callback.IntermediatePaymentData
import com.google.android.gms.wallet.callback.OnCompleteListener
import com.google.android.gms.wallet.callback.PaymentDataRequestUpdate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import org.json.JSONArray
import org.json.JSONObject

/**
 * Recomputes totals when the buyer changes their shipping address or selected
 * shipping option in the Google Pay sheet.
 *
 * The handler must have a public no-argument constructor. Google Pay creates it
 * through a service. Do not retain an Activity, ViewModel, or composable in it.
 */
interface GooglePayShippingHandler {
    suspend fun recompute(request: GooglePayShippingUpdateRequest): GooglePayShippingUpdateResult
}

/**
 * The buyer's in-progress shipping selection, passed to [GooglePayShippingHandler.recompute].
 *
 * @param shippingAddress the buyer's address as Google Pay redacts it before the
 * buyer authorizes payment: only [ShippingAddress.countryCode], [ShippingAddress.locality],
 * [ShippingAddress.administrativeArea] and [ShippingAddress.postalCode] are ever
 * populated here (no name or street lines, unlike the final [TokenResponse]).
 * Null if shipping address collection is disabled.
 */
data class GooglePayShippingUpdateRequest(
    val transaction: Transaction,
    val selectedShippingOption: ShippingOption,
    val shippingAddress: ShippingAddress?,
)

/** Which part of the buyer's shipping selection triggered the callback. */
enum class GooglePayShippingIntent(internal val googlePayValue: String) {
    ShippingAddress("SHIPPING_ADDRESS"),
    ShippingOption("SHIPPING_OPTION"),
}

/** A typed Google Pay error reason for a shipping update rejection. */
enum class GooglePayShippingErrorReason(internal val googlePayValue: String) {
    OtherError("OTHER_ERROR"),
    ShippingAddressInvalid("SHIPPING_ADDRESS_INVALID"),
    ShippingAddressUnserviceable("SHIPPING_ADDRESS_UNSERVICEABLE"),
    ShippingOptionInvalid("SHIPPING_OPTION_INVALID"),
}

/** The merchant decision returned from [GooglePayShippingHandler]. */
sealed interface GooglePayShippingUpdateResult {
    data class Accept(val lineItems: List<LineItem>, val total: Amount) : GooglePayShippingUpdateResult

    data class Reject(
        val message: String,
        val intent: GooglePayShippingIntent,
        val reason: GooglePayShippingErrorReason = GooglePayShippingErrorReason.OtherError,
    ) : GooglePayShippingUpdateResult
}

/**
 * Enables Google Pay's dynamic shipping callback with [handler].
 *
 * Google Pay invokes the handler every time the buyer changes their shipping
 * address or selected shipping option, so totals can be recomputed against the
 * fixed [Transaction.shippingOptions] list while the sheet stays open. Requires
 * [Transaction.shippingOptions] to be non-empty; every recompute is rejected
 * otherwise.
 */
data class GooglePayShippingConfig(
    val handler: Class<out GooglePayShippingHandler>,
    val timeoutMillis: Long = DEFAULT_TIMEOUT_MILLIS,
) {
    init {
        require(timeoutMillis > 0) { "Google Pay shipping timeout must be positive" }
    }

    companion object {
        const val DEFAULT_TIMEOUT_MILLIS = 10_000L
    }
}

internal data class StoredGooglePayShippingConfig(
    val handlerName: String,
    val timeoutMillis: Long,
)

internal object GooglePayShippingConfigStore {
    private const val PREFS_FILE = "evervault_google_pay_shipping"
    private const val HANDLER = "handler"
    private const val TIMEOUT_MILLIS = "timeout_millis"

    fun save(context: Context, config: Config) {
        val preferences = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
        val shipping = config.googlePayShipping
        val editor = preferences.edit()
        if (shipping == null) {
            editor.clear().apply()
            return
        }
        editor
            .putString(HANDLER, shipping.handler.name)
            .putLong(TIMEOUT_MILLIS, shipping.timeoutMillis)
            .apply()
    }

    fun load(context: Context): StoredGooglePayShippingConfig? {
        val preferences = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
        val handlerName = preferences.getString(HANDLER, null) ?: return null
        return StoredGooglePayShippingConfig(
            handlerName = handlerName,
            timeoutMillis = preferences.getLong(TIMEOUT_MILLIS, GooglePayShippingConfig.DEFAULT_TIMEOUT_MILLIS),
        )
    }
}

/**
 * Remembers the in-progress [Transaction] and the buyer's last-selected shipping
 * option id for a single Google Pay sheet attempt.
 *
 * In-memory rather than persisted: [EvervaultPaymentDataCallbacksService] runs
 * inside the app's own process (bound, not a separate `android:process`), and
 * the sheet cannot outlive that process, so there is no scenario where
 * disk-backed recovery would help. Holding a full [Transaction] (with its
 * [Array] of [LineItem] and non-serializable [Amount]) in `SharedPreferences`
 * would also require hand-rolled serialization for types never designed for it.
 */
internal object GooglePayShippingStateStore {
    @Volatile
    private var state: State? = null

    internal data class State(
        val transaction: Transaction,
        val merchantName: String,
        val selectedShippingOptionId: String?,
    )

    @Synchronized
    fun start(transaction: Transaction, merchantName: String) {
        state = State(
            transaction = transaction,
            merchantName = merchantName,
            selectedShippingOptionId = transaction.defaultShippingOptionId,
        )
    }

    @Synchronized
    fun current(): State? = state

    @Synchronized
    fun updateSelectedShippingOptionId(id: String) {
        state = state?.copy(selectedShippingOptionId = id)
    }

    @Synchronized
    fun clear() {
        state = null
    }
}

/** Raised internally to short-circuit [GooglePayShippingCoordinator.recompute] with a typed rejection. */
private class ShippingRejection(
    message: String,
    val intent: GooglePayShippingIntent,
    val reason: GooglePayShippingErrorReason,
) : Exception(message)

internal object GooglePayShippingCoordinator {
    @JvmStatic
    fun recompute(
        context: Context,
        intermediatePaymentData: IntermediatePaymentData,
        onCompleteListener: OnCompleteListener<PaymentDataRequestUpdate>,
    ) {
        CoroutineScope(Dispatchers.IO).launch {
            val callback = try {
                JSONObject(intermediatePaymentData.toJson())
            } catch (error: Exception) {
                Log.e(EvervaultPayViewModel.LOG_TAG, "Could not parse Google Pay shipping callback", error)
                onCompleteListener.complete(
                    shippingError("Something went wrong, please try again", GooglePayShippingIntent.ShippingAddress),
                )
                return@launch
            }

            val intent = if (callback.optString("callbackTrigger") == "SHIPPING_OPTION") {
                GooglePayShippingIntent.ShippingOption
            } else {
                GooglePayShippingIntent.ShippingAddress
            }

            val result = try {
                val config = GooglePayShippingConfigStore.load(context)
                    ?: error("Google Pay shipping is not configured")
                val state = GooglePayShippingStateStore.current()
                    ?: error("No Google Pay transaction is in progress")

                val optionId = callback.optJSONObject("shippingOptionData")?.optString("id")?.takeIf { it.isNotEmpty() }
                    ?: state.selectedShippingOptionId
                    ?: state.transaction.shippingOptions.firstOrNull()?.id

                val selectedShippingOption = state.transaction.shippingOptions.find { it.id == optionId }
                    ?: throw ShippingRejection(
                        "Select a shipping option to continue",
                        GooglePayShippingIntent.ShippingOption,
                        GooglePayShippingErrorReason.ShippingOptionInvalid,
                    )

                GooglePayShippingStateStore.updateSelectedShippingOptionId(selectedShippingOption.id)

                val shippingAddress = callback.optJSONObject("shippingAddress")?.let(::extractIntermediateShippingAddress)

                val request = GooglePayShippingUpdateRequest(
                    transaction = state.transaction,
                    selectedShippingOption = selectedShippingOption,
                    shippingAddress = shippingAddress,
                )

                shippingUpdate(
                    withTimeout(config.timeoutMillis) {
                        createHandler(config.handlerName).recompute(request)
                    },
                    state.transaction,
                    state.merchantName,
                )
            } catch (rejection: ShippingRejection) {
                shippingError(rejection.message ?: "Invalid shipping selection", rejection.intent, rejection.reason)
            } catch (error: CancellationException) {
                if (error is TimeoutCancellationException) {
                    Log.e(EvervaultPayViewModel.LOG_TAG, "Google Pay shipping recompute timed out", error)
                    shippingError("Updating totals timed out. Please try again", intent)
                } else {
                    Log.e(EvervaultPayViewModel.LOG_TAG, "Google Pay shipping recompute was cancelled", error)
                    shippingError("Updating totals was cancelled. Please try again", intent)
                }
            } catch (error: Exception) {
                Log.e(EvervaultPayViewModel.LOG_TAG, "Google Pay shipping recompute failed", error)
                shippingError("Something went wrong, please try again", intent)
            }
            onCompleteListener.complete(result)
        }
    }

    internal fun createHandler(name: String): GooglePayShippingHandler =
        Class.forName(name)
            .asSubclass(GooglePayShippingHandler::class.java)
            .getDeclaredConstructor()
            .newInstance()
}

/** Google Pay's shipping address as it appears mid-flow: redacted, no name or street lines. */
internal fun extractIntermediateShippingAddress(address: JSONObject): ShippingAddress =
    ShippingAddress(
        name = null,
        postalCode = address.optString("postalCode").takeIf { it.isNotEmpty() },
        countryCode = address.optString("countryCode").takeIf { it.isNotEmpty() },
        address1 = null,
        address2 = null,
        address3 = null,
        locality = address.optString("locality").takeIf { it.isNotEmpty() },
        administrativeArea = address.optString("administrativeArea").takeIf { it.isNotEmpty() },
        sortingCode = null,
    )

internal fun shippingUpdate(
    result: GooglePayShippingUpdateResult,
    transaction: Transaction,
    merchantName: String,
): PaymentDataRequestUpdate = when (result) {
    is GooglePayShippingUpdateResult.Accept ->
        PaymentDataRequestUpdate.fromJson(
            JSONObject()
                .put(
                    "newTransactionInfo", JSONObject()
                        .put("displayItems", JSONArray(result.lineItems.map {
                            JSONObject()
                                .put("label", it.label)
                                .put("type", "LINE_ITEM")
                                .put("price", it.amount.format(transaction.currency))
                                .put("status", "FINAL")
                        }))
                        .put("totalPriceLabel", transaction.priceLabel ?: defaultPriceLabel(merchantName))
                        .put("totalPrice", result.total.format(transaction.currency))
                        .put("totalPriceStatus", "FINAL")
                        .put("countryCode", transaction.country)
                        .put("currencyCode", transaction.currency),
                )
                .toString(),
        )

    is GooglePayShippingUpdateResult.Reject -> shippingError(result.message, result.intent, result.reason)
}

internal fun shippingError(
    message: String,
    intent: GooglePayShippingIntent,
    reason: GooglePayShippingErrorReason = GooglePayShippingErrorReason.OtherError,
): PaymentDataRequestUpdate =
    PaymentDataRequestUpdate.fromJson(
        JSONObject()
            .put(
                "error",
                JSONObject()
                    .put("message", message)
                    .put("reason", reason.googlePayValue)
                    .put("intent", intent.googlePayValue),
            )
            .toString(),
    )
