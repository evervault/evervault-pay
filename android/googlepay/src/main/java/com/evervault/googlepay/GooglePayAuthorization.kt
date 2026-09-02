package com.evervault.googlepay

import android.content.Context
import android.util.Log
import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.callback.OnCompleteListener
import com.google.android.gms.wallet.callback.PaymentAuthorizationResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import org.json.JSONObject

/**
 * Decides whether Google Pay can complete after Evervault decrypts the payment.
 *
 * The handler must have a public no-argument constructor. Google Pay creates it
 * through a service. Do not retain an Activity, ViewModel, or composable in it.
 */
interface GooglePayAuthorizationHandler {
    suspend fun authorize(payment: TokenResponse): GooglePayAuthorizationResult
}

/** A typed Google Pay error reason for an inline authorization rejection. */
enum class GooglePayAuthorizationErrorReason(internal val googlePayValue: String) {
    OtherError("OTHER_ERROR"),
    PaymentDataInvalid("PAYMENT_DATA_INVALID"),
    PaymentMethodInvalid("PAYMENT_METHOD_INVALID"),
    ShippingAddressInvalid("SHIPPING_ADDRESS_INVALID"),
    ShippingOptionInvalid("SHIPPING_OPTION_INVALID"),
    ShippingOptionUnsupported("SHIPPING_OPTION_UNSUPPORTED"),
}

/** The merchant decision returned from [GooglePayAuthorizationHandler]. */
sealed interface GooglePayAuthorizationResult {
    data object Accept : GooglePayAuthorizationResult

    data class Reject(
        val message: String,
        val reason: GooglePayAuthorizationErrorReason = GooglePayAuthorizationErrorReason.OtherError,
    ) : GooglePayAuthorizationResult
}

/**
 * Enables inline Google Pay authorization with [handler].
 *
 * Google Pay creates the handler after the buyer authorizes payment. The SDK
 * decrypts the payment, awaits [GooglePayAuthorizationHandler.authorize], and
 * returns the decision while the Google Pay sheet remains open.
 */
data class GooglePayAuthorizationConfig(
    val handler: Class<out GooglePayAuthorizationHandler>,
    val timeoutMillis: Long = DEFAULT_TIMEOUT_MILLIS,
) {
    init {
        require(timeoutMillis > 0) { "Google Pay authorization timeout must be positive" }
    }

    companion object {
        const val DEFAULT_TIMEOUT_MILLIS = 30_000L
    }
}

internal data class StoredGooglePayAuthorizationConfig(
    val appId: String,
    val merchantId: String,
    val apiBaseUrl: String,
    val handlerName: String,
    val timeoutMillis: Long,
)

internal object GooglePayAuthorizationConfigStore {
    private const val PREFS_FILE = "evervault_google_pay_authorization"
    private const val APP_ID = "app_id"
    private const val MERCHANT_ID = "merchant_id"
    private const val API_BASE_URL = "api_base_url"
    private const val HANDLER = "handler"
    private const val TIMEOUT_MILLIS = "timeout_millis"

    fun save(context: Context, config: Config) {
        val preferences = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
        val authorization = config.googlePayAuthorization
        val editor = preferences.edit()
        if (authorization == null) {
            editor.clear().apply()
            return
        }
        editor
            .putString(APP_ID, config.appId)
            .putString(MERCHANT_ID, config.merchantId)
            .putString(API_BASE_URL, EvervaultCustomConfig.apiBaseUrl)
            .putString(HANDLER, authorization.handler.name)
            .putLong(TIMEOUT_MILLIS, authorization.timeoutMillis)
            .apply()
    }

    fun load(context: Context): StoredGooglePayAuthorizationConfig? {
        val preferences = context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)
        val appId = preferences.getString(APP_ID, null) ?: return null
        val merchantId = preferences.getString(MERCHANT_ID, null) ?: return null
        val apiBaseUrl = preferences.getString(API_BASE_URL, null) ?: return null
        val handlerName = preferences.getString(HANDLER, null) ?: return null
        return StoredGooglePayAuthorizationConfig(
            appId = appId,
            merchantId = merchantId,
            apiBaseUrl = apiBaseUrl,
            handlerName = handlerName,
            timeoutMillis = preferences.getLong(TIMEOUT_MILLIS, GooglePayAuthorizationConfig.DEFAULT_TIMEOUT_MILLIS),
        )
    }
}

internal object GooglePayAuthorizationCoordinator {
    @JvmStatic
    fun authorize(
        context: Context,
        paymentData: PaymentData,
        onCompleteListener: OnCompleteListener<PaymentAuthorizationResult>,
    ) {
        CoroutineScope(Dispatchers.IO).launch {
            val result = try {
                val config = GooglePayAuthorizationConfigStore.load(context)
                    ?: error("Google Pay authorization is not configured")
                val payment = decryptPaymentData(
                    EvervaultPayAPI(config.apiBaseUrl, config.appId),
                    paymentData,
                    config.merchantId,
                )
                val decision = withTimeout(config.timeoutMillis) {
                    createHandler(config.handlerName).authorize(payment)
                }
                if (decision is GooglePayAuthorizationResult.Accept) {
                    // Only clear on Accept: a Reject keeps the Google Pay sheet open
                    // for the buyer to retry, and the retry needs the same shipping
                    // state (option, selected address) that a clear would erase.
                    GooglePayShippingStateStore.clear()
                }
                authorizationResult(decision)
            } catch (error: CancellationException) {
                if (error is TimeoutCancellationException) {
                    Log.e(EvervaultPayViewModel.LOG_TAG, "Google Pay authorization timed out", error)
                    authorizationError("Payment authorization timed out. Please try again")
                } else {
                    Log.e(EvervaultPayViewModel.LOG_TAG, "Google Pay authorization was cancelled", error)
                    authorizationError("Payment authorization was cancelled. Please try again")
                }
            } catch (error: Exception) {
                Log.e(EvervaultPayViewModel.LOG_TAG, "Google Pay authorization failed", error)
                authorizationError("Something went wrong, please try again")
            }
            onCompleteListener.complete(result)
        }
    }

    internal fun createHandler(name: String): GooglePayAuthorizationHandler =
        Class.forName(name)
            .asSubclass(GooglePayAuthorizationHandler::class.java)
            .getDeclaredConstructor()
            .newInstance()
}

internal fun authorizationResult(
    result: GooglePayAuthorizationResult,
): PaymentAuthorizationResult = when (result) {
    GooglePayAuthorizationResult.Accept ->
        PaymentAuthorizationResult.fromJson("{\"transactionState\":\"SUCCESS\"}")
    is GooglePayAuthorizationResult.Reject ->
        authorizationError(result.message, result.reason)
}

internal fun authorizationError(
    message: String,
    reason: GooglePayAuthorizationErrorReason = GooglePayAuthorizationErrorReason.PaymentDataInvalid,
): PaymentAuthorizationResult =
    PaymentAuthorizationResult.fromJson(
        JSONObject()
            .put("transactionState", "ERROR")
            .put(
                "error",
                JSONObject()
                    .put("message", message)
                    .put("reason", reason.googlePayValue)
                    .put("intent", "PAYMENT_AUTHORIZATION"),
            )
            .toString(),
    )
