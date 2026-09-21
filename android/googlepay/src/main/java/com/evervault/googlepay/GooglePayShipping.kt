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
 * Called when the buyer changes their shipping address or selected shipping
 * option in the Google Pay sheet. Can accept the selection (with a recomputed
 * total), reject it, or replace the shipping-option list itself - see
 * [GooglePayShippingUpdateResult].
 *
 * Must have a public no-argument constructor: Google Pay creates it through a
 * service, so don't retain an Activity, ViewModel, or composable in it.
 */
interface GooglePayShippingHandler {
    suspend fun recompute(request: GooglePayShippingUpdateRequest): GooglePayShippingUpdateResult
}

/**
 * The buyer's in-progress shipping selection, passed to [GooglePayShippingHandler.recompute].
 *
 * @param transaction the transaction as of the last accepted update, not the original -
 * resolve against it idempotently (e.g. by recomputing a replacement list from a canonical
 * source) rather than assuming it matches what the buyer first saw.
 * @param shippingAddress redacted until the buyer authorizes payment: only
 * [ShippingAddress.countryCode], [ShippingAddress.locality],
 * [ShippingAddress.administrativeArea] and [ShippingAddress.postalCode] are populated.
 * Null if shipping address collection is disabled.
 * @param trigger which part of the selection changed to cause this callback.
 * Google Pay's initial callback is reported as [GooglePayShippingIntent.ShippingAddress].
 */
data class GooglePayShippingUpdateRequest(
    val transaction: Transaction,
    val selectedShippingOption: ShippingOption,
    val shippingAddress: ShippingAddress?,
    val trigger: GooglePayShippingIntent,
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
    /**
     * Accepts the current selection with a recomputed total, e.g. a destination-specific rate.
     *
     * [lineItems] and [total] are optional - omit either to leave it unchanged.
     *
     * [shippingOptions] is also optional and, when set, replaces the sheet's shipping-option
     * list for the rest of this attempt - e.g. offering pickup only in certain destinations.
     * [defaultShippingOptionId] picks which of [shippingOptions] to preselect; if omitted, the
     * buyer's previous selection carries over when it still exists in the new list.
     */
    data class Accept(
        val lineItems: List<LineItem>? = null,
        val total: Amount? = null,
        val shippingOptions: List<ShippingOption>? = null,
        val defaultShippingOptionId: String? = null,
    ) : GooglePayShippingUpdateResult {
        init {
            if (shippingOptions != null) {
                require(shippingOptions.isNotEmpty()) { "A replacement shippingOptions list must not be empty" }
            }
            if (defaultShippingOptionId != null) {
                require(shippingOptions != null) {
                    "defaultShippingOptionId requires a replacement shippingOptions list"
                }
                require(shippingOptions.any { it.id == defaultShippingOptionId }) {
                    "defaultShippingOptionId \"$defaultShippingOptionId\" must match the id of one of shippingOptions"
                }
            }
        }
    }

    /**
     * Rejects the current selection, e.g. an unserviceable country.
     *
     * This is UX guidance, not a hard gate: Google Pay shows the error but doesn't
     * reliably block the buyer from pressing Pay anyway. Re-validate server-side.
     */
    data class Reject(
        val message: String,
        val intent: GooglePayShippingIntent,
        val reason: GooglePayShippingErrorReason = GooglePayShippingErrorReason.OtherError,
    ) : GooglePayShippingUpdateResult
}

/**
 * Enables Google Pay's dynamic shipping callback with [handler].
 *
 * Google Pay invokes [handler] on every address or shipping-option change so
 * the total, line items, and the [Transaction.shippingOptions] list itself
 * can be recomputed while the sheet stays open.
 *
 * Required whenever [Transaction.shippingOptions] is non-empty - that's how
 * Google Pay reports the buyer's selection back to you. Without a handler,
 * every recompute is rejected.
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
    fun updateTransaction(transaction: Transaction) {
        state = state?.copy(transaction = transaction)
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

            val intent = extractShippingTrigger(callback)

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
                    trigger = intent,
                )

                val handlerResult = withTimeout(config.timeoutMillis) {
                    createHandler(config.handlerName).recompute(request)
                }

                val updatedTransaction = if (handlerResult is GooglePayShippingUpdateResult.Accept) {
                    mergedTransaction(state.transaction, handlerResult, selectedShippingOption.id).also { merged ->
                        GooglePayShippingStateStore.updateTransaction(merged)
                        // Only re-sync the selection when the shippin options list actually changed.
                        if (handlerResult.shippingOptions != null) {
                            merged.defaultShippingOptionId?.let(GooglePayShippingStateStore::updateSelectedShippingOptionId)
                        }
                    }
                } else {
                    state.transaction
                }

                shippingUpdate(handlerResult, updatedTransaction, state.merchantName)
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

/**
 * Which part of the buyer's selection triggered this callback.
 * Per Google Pay's `callbackTrigger`, only SHIPPING_OPTION and SHIPPING_ADDRESS 
 * map to a real intent here. Anything else defaults to ShippingAddress.
 */
internal fun extractShippingTrigger(callback: JSONObject): GooglePayShippingIntent =
    if (callback.optString("callbackTrigger") == "SHIPPING_OPTION") {
        GooglePayShippingIntent.ShippingOption
    } else {
        GooglePayShippingIntent.ShippingAddress
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

/**
 * Merges [accept] into [current]. If the shipping list changes, the new selection is:
 * buyer's previous pick (if still valid) > [accept]'s default > first option in the list.
 */
internal fun mergedTransaction(
    current: Transaction,
    accept: GooglePayShippingUpdateResult.Accept,
    previousSelectionId: String? = null,
): Transaction {
    val shippingOptions = accept.shippingOptions ?: current.shippingOptions
    val defaultShippingOptionId = when {
        accept.shippingOptions == null -> current.defaultShippingOptionId
        previousSelectionId != null && shippingOptions.any { it.id == previousSelectionId } -> previousSelectionId
        accept.defaultShippingOptionId != null -> accept.defaultShippingOptionId
        else -> shippingOptions.firstOrNull()?.id
    }

    return current.copy(
        lineItems = accept.lineItems?.toTypedArray() ?: current.lineItems,
        total = accept.total ?: current.total,
        shippingOptions = shippingOptions,
        defaultShippingOptionId = defaultShippingOptionId,
    )
}

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
                        .put("displayItems", JSONArray((result.lineItems ?: transaction.lineItems.toList()).map {
                            JSONObject()
                                .put("label", it.label)
                                .put("type", it.type.name)
                                .put("price", it.amount.format(transaction.currency))
                                .put("status", "FINAL")
                        }))
                        .put("totalPriceLabel", transaction.priceLabel ?: defaultPriceLabel(merchantName))
                        .put("totalPrice", (result.total ?: transaction.total).format(transaction.currency))
                        .put("totalPriceStatus", "FINAL")
                        .put("countryCode", transaction.country)
                        .put("currencyCode", transaction.currency),
                )
                .apply {
                    if (result.shippingOptions != null) {
                        put(
                            "newShippingOptionParameters",
                            shippingOptionParametersJson(transaction.shippingOptions, transaction.defaultShippingOptionId),
                        )
                    }
                }
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
