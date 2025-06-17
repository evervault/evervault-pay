package com.evervault.evpay

import android.content.Context
import androidx.activity.result.ActivityResultLauncher
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.google.pay.button.PayButton
import com.google.android.gms.tasks.Task
import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.PaymentDataRequest
import com.google.android.gms.wallet.PaymentsClient
import com.google.android.gms.wallet.Wallet
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

abstract class PaymentUiState internal constructor() {
    object NotStarted : PaymentUiState()
    object Available : PaymentUiState()
    class PaymentCompleted(val payerName: String) : PaymentUiState()
    class Error(val code: Int, val message: String? = null) : PaymentUiState()
}

/**
 * Create a Google Pay API base request object with properties used in all requests.
 *
 * @return Google Pay API base request object.
 * @throws JSONException
 */
private val baseRequest = JSONObject()
    .put("apiVersion", 2)
    .put("apiVersionMinor", 0)

/**
 * Describe your app's support for the CARD payment method.
 *
 *
 * The provided properties are applicable to both an IsReadyToPayRequest and a
 * PaymentDataRequest.
 *
 * @return A CARD PaymentMethod object describing accepted cards.
 * @throws JSONException
 * See [PaymentMethod](https://developers.google.com/pay/api/android/reference/object.PaymentMethod)
 */
// Optionally, you can add billing address/phone number associated with a CARD payment method.
private fun baseCardPaymentMethod(model: EvervaultPayViewModel): JSONObject =
    JSONObject()
        .put("type", "CARD")
        .put("parameters", JSONObject()
            .put("allowedAuthMethods", JSONArray(model.SUPPORTED_METHODS))
            .put("allowedCardNetworks", JSONArray(model.SUPPORTED_NETWORKS))
            .put("billingAddressRequired", true)
            .put("billingAddressParameters", JSONObject()
                .put("format", "FULL")
            )
        )

private fun allowedPaymentMethods(model: EvervaultPayViewModel) = JSONArray().put(baseCardPaymentMethod(model)
    .put("tokenizationSpecification", JSONObject()
        .put("type", "PAYMENT_GATEWAY")
        .put("parameters", JSONObject(model.PAYMENT_GATEWAY_TOKENIZATION_PARAMETERS))))

/**
 * An object describing accepted forms of payment by your app, used to determine a viewer's
 * readiness to pay.
 *
 * @return API version and payment methods supported by the app.
 * See [IsReadyToPayRequest](https://developers.google.com/pay/api/android/reference/object.IsReadyToPayRequest)
 */
fun isReadyToPayRequest(model: EvervaultPayViewModel): JSONObject? =
    try {
        baseRequest
            .put("allowedPaymentMethods", JSONArray().put(baseCardPaymentMethod(model)))
    } catch (e: JSONException) {
        null
    }

/**
 * Creates an instance of [PaymentsClient] for use in an [Context] using the
 * environment and theme set in [Constants].
 *
 * @param context from the caller activity.
 */
fun createPaymentsClient(context: Context, environment: Int): PaymentsClient {
    val walletOptions = Wallet.WalletOptions.Builder()
        .setEnvironment(environment)
        .build()

    return Wallet.getPaymentsClient(context, walletOptions)
}

@Composable
fun EvervaultPaymentButton(modifier: Modifier, paymentRequest: Transaction, model: EvervaultPayViewModel, displayPaymentModalLauncher: ActivityResultLauncher<Task<PaymentData>>) {
    val onClickHandler: () -> Unit = {
        // https://developers.google.com/pay/api/web/reference/request-objects#TransactionInfo
        val paymentDataRequestJson = baseRequest
            .put("allowedPaymentMethods", allowedPaymentMethods(model))
            .put("transactionInfo", JSONObject()
                .put("displayItems", JSONArray(paymentRequest.lineItems.map {
                    JSONObject()
                        .put("label", it.label)
                        .put("type", "LINE_ITEM")
                        .put("price", it.amount.amount)
                        .put("status", "FINAL")
                }))
                .put("totalPriceLabel", "Total")
                .put("totalPrice", paymentRequest.lineItems.last().amount.amount)
                .put("totalPriceStatus", "FINAL")
                .put("countryCode", paymentRequest.country)
                .put("currencyCode", paymentRequest.currency))
            .put("merchantInfo", JSONObject().put("merchantName", model.MERCHANT_NAME))
        val request = PaymentDataRequest.fromJson(paymentDataRequestJson.toString())

        val task = model.paymentsClient.loadPaymentData(request)
        task.addOnCompleteListener(displayPaymentModalLauncher::launch)
    }

    // TODO: Pass in button customizations
    PayButton(
        modifier = modifier,
        onClick = onClickHandler,
        allowedPaymentMethods = allowedPaymentMethods(model).toString()
    )
}
