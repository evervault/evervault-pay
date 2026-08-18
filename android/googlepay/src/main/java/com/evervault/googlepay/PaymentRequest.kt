package com.evervault.googlepay

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

internal fun gatewayTokenizationParameters(config: Config) = mapOf(
    "gateway" to Constants.GATEWAY_TOKENIZATION_NAME,
    "gatewayMerchantId" to config.merchantId
)

private fun gatewayTokenizationSpecification(config: Config) = JSONObject()
    .put("type", "PAYMENT_GATEWAY")
    .put("parameters", JSONObject(gatewayTokenizationParameters(config)))

private fun allowedCardNetworks(config: Config) = JSONArray(config.supportedNetworks.map { it.name })

private fun baseCardPaymentMethod(config: Config): JSONObject {
    val billingAddress = config.billingAddress as? BillingAddressConfig.Enabled

    val parameters = JSONObject()
        .put("allowedAuthMethods", JSONArray(config.supportedMethods.asGooglePayStrings()))
        .put("allowedCardNetworks", allowedCardNetworks(config))
        .put("billingAddressRequired", billingAddress != null)

    if (billingAddress != null) {
        parameters.put("billingAddressParameters", JSONObject()
            .put("format", billingAddress.format.name)
            .put("phoneNumberRequired", billingAddress.phoneNumber)
        )
    }

    return JSONObject()
        .put("type", "CARD")
        .put("parameters", parameters)
}

private fun cardPaymentMethod(config: Config) = baseCardPaymentMethod(config)
    .put("tokenizationSpecification", gatewayTokenizationSpecification(config))

internal fun allowedPaymentMethods(config: Config) = JSONArray().put(cardPaymentMethod(config))

internal fun baseRequest() = JSONObject()
    .put("apiVersion", 2)
    .put("apiVersionMinor", 0)

fun isReadyToPayRequest(model: EvervaultPayViewModel): JSONObject? = isReadyToPayRequest(model.config)

internal fun isReadyToPayRequest(config: Config): JSONObject? =
    try {
        baseRequest()
            .put("allowedPaymentMethods", JSONArray().put(baseCardPaymentMethod(config)))
    } catch (e: JSONException) {
        null
    }

// https://developers.google.com/pay/api/web/reference/request-objects#TransactionInfo
internal fun buildPaymentRequestJson(
    config: Config,
    transaction: Transaction,
    merchantName: String
): String =
    baseRequest()
        .put("emailRequired", config.emailRequired)
        .put("allowedPaymentMethods", allowedPaymentMethods(config))
        .put(
            "transactionInfo", JSONObject()
                .put("displayItems", JSONArray(transaction.lineItems.map {
                    JSONObject()
                        .put("label", it.label)
                        .put("type", "LINE_ITEM")
                        .put("price", it.amount.format(transaction.currency))
                        .put("status", "FINAL")
                }))
                .put("totalPriceLabel", "Total")
                .put("totalPrice", transaction.total.format(transaction.currency))
                .put("totalPriceStatus", "FINAL")
                .put("countryCode", transaction.country)
                .put("currencyCode", transaction.currency)
        )
        .put("merchantInfo", JSONObject().put("merchantName", merchantName))
        .toString()
