package com.evervault.googlepay

import android.app.Activity
import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.google.pay.button.PayButton
import com.google.android.gms.tasks.Task
import com.google.android.gms.wallet.AutoResolveHelper
import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.PaymentDataRequest
import com.google.android.gms.wallet.PaymentsClient
import com.google.android.gms.wallet.Wallet
import com.google.pay.button.ButtonTheme
import com.google.pay.button.ButtonType
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

abstract class PaymentState internal constructor() {
    object NotStarted : PaymentState()
    object Available : PaymentState()
    object Unavailable: PaymentState()
    class PaymentCompleted(val response: DpanResponse) : PaymentState()
    class Error(val code: Int, val message: String? = null) : PaymentState()
}


/**
 * Gateway Integration: Identify your gateway and your app's gateway merchant identifier.
 *
 *
 * The Google Pay API response will return an encrypted payment method capable of being charged
 * by a supported gateway after payer authorization.
 *
 * @return Payment data tokenization for the CARD payment method.
 * @throws JSONException
 * See [PaymentMethodTokenizationSpecification](https://developers.google.com/pay/api/android/reference/object.PaymentMethodTokenizationSpecification)
 */
private fun gatewayTokenizationSpecification(model: EvervaultPayViewModel) = JSONObject()
        .put("type", "PAYMENT_GATEWAY")
        .put("parameters", JSONObject(model.PAYMENT_GATEWAY_TOKENIZATION_PARAMETERS))

/**
 * Card networks supported by your app and your gateway.
 *
 * @return Allowed card networks
 * See [CardParameters](https://developers.google.com/pay/api/android/reference/object.CardParameters)
 */
private fun allowedCardNetworks(config: Config) = JSONArray(config.supportedNetworks.map { it.name })

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
            .put("allowedAuthMethods", JSONArray(model.config.supportedMethods))
            .put("allowedCardNetworks", allowedCardNetworks(model.config))
            .put("billingAddressRequired", true)
            .put("billingAddressParameters", JSONObject()
                .put("format", "FULL")
            )
        )

/**
 * Describe the expected returned payment data for the CARD payment method
 *
 * @return A CARD PaymentMethod describing accepted cards and optional fields.
 * @throws JSONException
 * See [PaymentMethod](https://developers.google.com/pay/api/android/reference/object.PaymentMethod)
 */
private fun cardPaymentMethod(model: EvervaultPayViewModel) = baseCardPaymentMethod(model)
    .put("tokenizationSpecification", gatewayTokenizationSpecification(model))

private fun allowedPaymentMethods(model: EvervaultPayViewModel) = JSONArray().put(cardPaymentMethod(model))

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

typealias ButtonTheme = com.google.pay.button.ButtonTheme
typealias ButtonType = com.google.pay.button.ButtonType

@Composable
fun EvervaultPaymentButton(
    modifier: Modifier,
    paymentRequest: Transaction,
    model: EvervaultPayViewModel,
    theme: ButtonTheme = ButtonTheme.Dark,
    type: ButtonType = ButtonType.Pay,
) {
    val activity = LocalContext.current as Activity

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
                .put("totalPrice", paymentRequest.total.amount)
                .put("totalPriceStatus", "FINAL")
                .put("countryCode", paymentRequest.country)
                .put("currencyCode", paymentRequest.currency))
            .put("merchantInfo", JSONObject().put("merchantName", model.MERCHANT_NAME))
        val request = PaymentDataRequest.fromJson(paymentDataRequestJson.toString())

        val task: Task<PaymentData> = model.paymentsClient.loadPaymentData(request)
        AutoResolveHelper.resolveTask(
            task,
            activity,
            EvervaultPayViewModel.LOAD_PAYMENT_DATA_REQUEST_CODE
        )
    }

    PayButton(
        modifier = modifier,
        onClick = onClickHandler,
        allowedPaymentMethods = allowedPaymentMethods(model).toString(),
        theme = theme,
        type = type,
    )
}
