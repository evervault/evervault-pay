package com.evervault.googlepay

import android.content.Context
import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.callback.OnCompleteListener
import com.google.android.gms.wallet.callback.PaymentAuthorizationResult
import com.google.gson.Gson
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import org.json.JSONObject

/**
 * Decides whether Google Pay can complete after Evervault decrypts the payment.
 *
 * The handler must have a public no-argument constructor. Google Pay invokes it
 * through a service, so do not retain an Activity, ViewModel, or composable in it.
 */
interface GooglePayAuthorizationHandler {
    suspend fun authorize(
        payment: TokenResponse,
        transaction: Transaction,
    ): GooglePayAuthorizationResult
}

/** The merchant decision returned from [GooglePayAuthorizationHandler]. */
sealed interface GooglePayAuthorizationResult {
    data object Accept : GooglePayAuthorizationResult

    data class Reject(
        val message: String,
        val reason: String = "OTHER_ERROR",
    ) : GooglePayAuthorizationResult
}

/**
 * Enables inline Google Pay authorization with [handler].
 *
 * Google Pay creates the handler after the buyer authorizes payment. The SDK
 * decrypts the payment, awaits [GooglePayAuthorizationHandler.authorize], and
 * returns the decision to Google Pay while its sheet remains open.
 */
data class GooglePayAuthorizationConfig(
    val handler: Class<out GooglePayAuthorizationHandler>,
)

internal data class StoredGooglePayAuthorizationConfig(
    val appId: String,
    val merchantId: String,
    val handlerName: String,
    val transaction: Transaction,
)

internal object GooglePayAuthorizationConfigStore {
    private const val PREFERENCES = "evervault_google_pay_authorization"
    private const val APP_ID = "app_id"
    private const val MERCHANT_ID = "merchant_id"
    private const val HANDLER = "handler"
    private const val TRANSACTION = "transaction"

    fun save(context: Context, config: Config) {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val authorization = config.googlePayAuthorization
        val editor = preferences.edit()
        if (authorization == null) {
            editor.remove(APP_ID).remove(MERCHANT_ID).remove(HANDLER).remove(TRANSACTION).apply()
            return
        }
        editor
            .putString(APP_ID, config.appId)
            .putString(MERCHANT_ID, config.merchantId)
            .putString(HANDLER, authorization.handler.name)
            .apply()
    }

    fun saveTransaction(context: Context, transaction: Transaction) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
            .putString(TRANSACTION, Gson().toJson(transaction))
            .apply()
    }

    fun load(context: Context): StoredGooglePayAuthorizationConfig? {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val appId = preferences.getString(APP_ID, null) ?: return null
        val merchantId = preferences.getString(MERCHANT_ID, null) ?: return null
        val handlerName = preferences.getString(HANDLER, null) ?: return null
        val transactionJson = preferences.getString(TRANSACTION, null) ?: return null
        val transaction = Gson().fromJson(transactionJson, Transaction::class.java) ?: return null
        return StoredGooglePayAuthorizationConfig(appId, merchantId, handlerName, transaction)
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
                    EvervaultPayAPI(EvervaultCustomConfig.apiBaseUrl, config.appId),
                    paymentData,
                    config.merchantId,
                )
                authorizationResult(
                    createHandler(config.handlerName).authorize(payment, config.transaction),
                )
            } catch (_: Exception) {
                authorizationError("Something went wrong, please try again")
            }
            onCompleteListener.complete(result)
        }
    }

    private fun createHandler(name: String): GooglePayAuthorizationHandler =
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
    reason: String = "OTHER_ERROR",
): PaymentAuthorizationResult =
    PaymentAuthorizationResult.fromJson(
        JSONObject()
            .put("transactionState", "ERROR")
            .put(
                "error",
                JSONObject()
                    .put("message", message)
                    .put("reason", reason)
                    .put("intent", "PAYMENT_AUTHORIZATION"),
            )
            .toString(),
    )
