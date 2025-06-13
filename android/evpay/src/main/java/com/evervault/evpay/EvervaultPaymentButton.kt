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
import com.google.android.gms.wallet.WalletConstants
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
 * The name of your payment processor/gateway. Please refer to their documentation for more
 * information.
 *
 * @value #PAYMENT_GATEWAY_TOKENIZATION_NAME
 */
private val PAYMENT_GATEWAY_TOKENIZATION_NAME = "example"

/**
 * Custom parameters required by the processor/gateway.
 * In many cases, your processor / gateway will only require a gatewayMerchantId.
 * Please refer to your processor's documentation for more information. The number of parameters
 * required and their names vary depending on the processor.
 *
 * @value #PAYMENT_GATEWAY_TOKENIZATION_PARAMETERS
 */
private val PAYMENT_GATEWAY_TOKENIZATION_PARAMETERS = mapOf(
    "gateway" to PAYMENT_GATEWAY_TOKENIZATION_NAME,
    "gatewayMerchantId" to "exampleGatewayMerchantId"
)

/**
 * The allowed networks to be requested from the API. If the user has cards from networks not
 * specified here in their account, these will not be offered for them to choose in the popup.
 *
 * @value #SUPPORTED_NETWORKS
 */
private val SUPPORTED_NETWORKS = CardNetwork.entries.map { it.name }

/**
 * The Google Pay API may return cards on file on Google.com (PAN_ONLY) and/or a device token on
 * an Android device authenticated with a 3-D Secure cryptogram (CRYPTOGRAM_3DS).
 *
 * @value #SUPPORTED_METHODS
 */
private val SUPPORTED_METHODS = listOf("CRYPTOGRAM_3DS")

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
 * Gateway Integration: Identify your gateway and your app's gateway merchant identifier.
 *
 *
 * The Google Pay API response will return an encrypted payment method capable of being charged
 * by a supported gateway after payer authorization.
 *
 *
 * TODO: Check with your gateway on the parameters to pass and modify them in Constants.java.
 *
 * @return Payment data tokenization for the CARD payment method.
 * @throws JSONException
 * See [PaymentMethodTokenizationSpecification](https://developers.google.com/pay/api/android/reference/object.PaymentMethodTokenizationSpecification)
 */
private val gatewayTokenizationSpecification: JSONObject =
    JSONObject()
        .put("type", "PAYMENT_GATEWAY")
        .put("parameters", JSONObject(PAYMENT_GATEWAY_TOKENIZATION_PARAMETERS))

/**
 * Card networks supported by your app and your gateway.
 *
 *
 * TODO: Confirm card networks supported by your app and gateway & update in Constants.java.
 *
 * @return Allowed card networks
 * See [CardParameters](https://developers.google.com/pay/api/android/reference/object.CardParameters)
 */
private val allowedCardNetworks = JSONArray(SUPPORTED_NETWORKS)

/**
 * Card authentication methods supported by your app and your gateway.
 *
 *
 * TODO: Confirm your processor supports Android device tokens on your supported card networks
 * and make updates in Constants.java.
 *
 * @return Allowed card authentication methods.
 * See [CardParameters](https://developers.google.com/pay/api/android/reference/object.CardParameters)
 */
private val allowedCardAuthMethods = JSONArray(SUPPORTED_METHODS)

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
private fun baseCardPaymentMethod(): JSONObject =
    JSONObject()
        .put("type", "CARD")
        .put("parameters", JSONObject()
            .put("allowedAuthMethods", allowedCardAuthMethods)
            .put("allowedCardNetworks", allowedCardNetworks)
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
private val cardPaymentMethod: JSONObject = baseCardPaymentMethod()
    .put("tokenizationSpecification", gatewayTokenizationSpecification)

private val allowedPaymentMethods: JSONArray = JSONArray().put(cardPaymentMethod)

/**
 * An object describing accepted forms of payment by your app, used to determine a viewer's
 * readiness to pay.
 *
 * @return API version and payment methods supported by the app.
 * See [IsReadyToPayRequest](https://developers.google.com/pay/api/android/reference/object.IsReadyToPayRequest)
 */
fun isReadyToPayRequest(): JSONObject? =
    try {
        baseRequest
            .put("allowedPaymentMethods", JSONArray().put(baseCardPaymentMethod()))
    } catch (e: JSONException) {
        null
    }

/**
 * Information about the merchant requesting payment information
 *
 * @return Information about the merchant.
 * @throws JSONException
 * See [MerchantInfo](https://developers.google.com/pay/api/android/reference/object.MerchantInfo)
 */
private val merchantInfo: JSONObject =
    JSONObject().put("merchantName", "Example Merchant")

/**
 * Creates an instance of [PaymentsClient] for use in an [Context] using the
 * environment and theme set in [Constants].
 *
 * @param context from the caller activity.
 */
fun createPaymentsClient(context: Context): PaymentsClient {
    val walletOptions = Wallet.WalletOptions.Builder()
        .setEnvironment(PAYMENTS_ENVIRONMENT)
        .build()

    return Wallet.getPaymentsClient(context, walletOptions)
}

/**
 * Provide Google Pay API with a payment amount, currency, and amount status.
 *
 * @return information about the requested payment.
 * @throws JSONException
 * See [TransactionInfo](https://developers.google.com/pay/api/android/reference/object.TransactionInfo)
 */
private fun getTransactionInfo(price: String, country: String, currency: String): JSONObject =
    JSONObject()
        .put("totalPrice", price)
        .put("totalPriceStatus", "FINAL")
        .put("countryCode", country)
        .put("currencyCode", currency)

/**
 * An object describing information requested in a Google Pay payment sheet
 *
 * @return Payment data expected by your app.
 * See [PaymentDataRequest](https://developers.google.com/pay/api/android/reference/object.PaymentDataRequest)
 */
fun getPaymentDataRequest(priceLabel: String, country: String, currency: String): JSONObject =
    baseRequest
        .put("allowedPaymentMethods", allowedPaymentMethods)
        .put("transactionInfo", getTransactionInfo(priceLabel, country, currency))
        .put("merchantInfo", merchantInfo)
        .put("shippingAddressRequired", true)
        .put("shippingAddressParameters", JSONObject()
            .put("phoneNumberRequired", false)
            .put("allowedCountryCodes", JSONArray(listOf("US", "GB")))
        )


/**
 * Changing this to ENVIRONMENT_PRODUCTION will make the API return chargeable card information.
 * Please refer to the documentation to read about the required steps needed to enable
 * ENVIRONMENT_PRODUCTION.
 *
 * @value #PAYMENTS_ENVIRONMENT
 */
private val PAYMENTS_ENVIRONMENT = WalletConstants.ENVIRONMENT_TEST

@Composable
fun EvervaultPaymentButton(modifier: Modifier, paymentRequest: Transaction, paymentsClient: PaymentsClient, onResult: ActivityResultLauncher<Task<PaymentData>>) {
    val onClickHandler: () -> Unit = {
        // https://developers.google.com/pay/api/web/reference/request-objects#TransactionInfo
        val paymentDataRequestJson = baseRequest
            .put("allowedPaymentMethods", allowedPaymentMethods)
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
            .put("merchantInfo", JSONObject().put("merchantName", "Example Merchant"))
        val request = PaymentDataRequest.fromJson(paymentDataRequestJson.toString())

        val task = paymentsClient.loadPaymentData(request)
        task.addOnCompleteListener(onResult::launch)
    }

    // TODO: Pass in button customizations
    PayButton(
        modifier = modifier,
        onClick = onClickHandler,
        allowedPaymentMethods = allowedPaymentMethods.toString()
    )
}
