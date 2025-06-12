package com.evervault.evpay

import androidx.activity.result.ActivityResultLauncher
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.google.pay.button.PayButton
import com.google.android.gms.tasks.Task
import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.PaymentDataRequest
import com.google.android.gms.wallet.PaymentsClient
import org.json.JSONArray
import org.json.JSONObject
import kotlin.enums.enumEntries

inline fun <reified T : Enum<T>> printAllValues() {
    println(enumEntries<T>().joinToString { it.name })
}

abstract class PaymentUiState internal constructor() {
    object NotStarted : PaymentUiState()
    object Available : PaymentUiState()
    class PaymentCompleted(val payerName: String) : PaymentUiState()
    class Error(val code: Int, val message: String? = null) : PaymentUiState()
}

private val SUPPORTED_METHODS = listOf("CRYPTOGRAM_3DS")
private val PAYMENT_GATEWAY_TOKENIZATION_NAME = "example"

private val baseRequest = JSONObject()
    .put("apiVersion", 2)
    .put("apiVersionMinor", 0)

// TODO: Add our merchant ID
private val gatewayTokenizationSpecification: JSONObject =
    JSONObject()
        .put("type", "PAYMENT_GATEWAY")
        .put("parameters", JSONObject(mapOf(
            "gateway" to PAYMENT_GATEWAY_TOKENIZATION_NAME,
            "gatewayMerchantId" to "exampleGatewayMerchantId"
        )))

@Composable
fun EvervaultPaymentButton(modifier: Modifier, paymentRequest: Transaction, paymentsClient: PaymentsClient, onResult: ActivityResultLauncher<Task<PaymentData>>) {
    val SUPPORTED_NETWORKS = listOf(
        "AMEX",
        "DISCOVER",
        "JCB",
        "MASTERCARD",
        "VISA")

    val allowedCardNetworks = JSONArray(SUPPORTED_NETWORKS)
    val allowedCardAuthMethods = JSONArray(SUPPORTED_METHODS)

    val allowedPaymentMethods: JSONArray = JSONArray().put(JSONObject()
        .put("type", "CARD")
        .put("parameters", JSONObject()
            .put("allowedAuthMethods", allowedCardAuthMethods)
            .put("allowedCardNetworks", allowedCardNetworks)
            .put("billingAddressRequired", true)
            .put("billingAddressParameters", JSONObject()
                .put("format", "FULL")
            )
        )
        .put("tokenizationSpecification", gatewayTokenizationSpecification))

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
