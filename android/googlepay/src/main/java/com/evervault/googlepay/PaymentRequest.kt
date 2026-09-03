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

    // Omit Google Pay defaults to preserve cross-SDK request parity.
    if (!config.allowPrepaidCards) parameters.put("allowPrepaidCards", false)
    if (!config.allowCreditCards) parameters.put("allowCreditCards", false)
    if (config.assuranceDetailsRequired) parameters.put("assuranceDetailsRequired", true)

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
            .apply {
                if (config.existingPaymentMethodRequired) {
                    put("existingPaymentMethodRequired", true)
                }
            }
    } catch (e: JSONException) {
        null
    }

internal fun defaultPriceLabel(merchantName: String) = "Pay $merchantName"

// https://developers.google.com/pay/api/web/reference/request-objects#ShippingAddressParameters
private fun shippingAddressParameters(shippingAddress: ShippingAddressConfig.Enabled): JSONObject {
    val parameters = JSONObject()
        .put("phoneNumberRequired", shippingAddress.phoneNumberRequired)

    if (shippingAddress.allowedCountryCodes != null) {
        parameters.put("allowedCountryCodes", JSONArray(shippingAddress.allowedCountryCodes))
    }

    return parameters
}

// https://developers.google.com/pay/api/web/reference/request-objects#ShippingOptionParameters
private fun shippingOptionParameters(transaction: Transaction): JSONObject {
    val parameters = JSONObject()
        .put("shippingOptions", JSONArray(transaction.shippingOptions.map {
            JSONObject()
                .put("id", it.id)
                // Google Pay has no price field of its own for a shipping option, so
                // the price is baked into the label. No currency symbol lookup exists
                // in this SDK (and symbols like "$" are ambiguous across currencies
                // anyway), so the ISO currency code is used instead.
                .put("label", "${it.label}: ${it.amount.format(transaction.currency)} ${transaction.currency}")
                .apply { if (it.description != null) put("description", it.description) }
        }))

    if (transaction.defaultShippingOptionId != null) {
        parameters.put("defaultSelectedOptionId", transaction.defaultShippingOptionId)
    }

    return parameters
}

// https://developers.google.com/pay/api/android/reference/request-objects#TransactionInfo
internal fun buildPaymentRequestJson(
    config: Config,
    transaction: Transaction,
    merchantName: String
): String {
    val shippingAddress = config.shippingAddress as? ShippingAddressConfig.Enabled
    val shippingOptionsEnabled = transaction.shippingOptions.isNotEmpty()

    return baseRequest()
        .put("emailRequired", config.emailRequired)
        .put("allowedPaymentMethods", allowedPaymentMethods(config))
        .put(
            "transactionInfo", JSONObject()
                .put("displayItems", JSONArray(transaction.lineItems.map {
                    JSONObject()
                        .put("label", it.label)
                        .put("type", it.type.name)
                        .put("price", it.amount.format(transaction.currency))
                        .put("status", "FINAL")
                }))
                .put("totalPriceLabel", transaction.priceLabel ?: defaultPriceLabel(merchantName))
                .put("totalPrice", transaction.total.format(transaction.currency))
                .put("totalPriceStatus", transaction.totalPriceStatus.name)
                .put("countryCode", transaction.country)
                .put("currencyCode", transaction.currency)
                .apply {
                    transaction.checkoutOption?.let { put("checkoutOption", it.name) }
                    transaction.transactionId?.let { put("transactionId", it) }
                }
        )
        .put("merchantInfo", JSONObject().put("merchantName", merchantName))
        .put("shippingAddressRequired", shippingAddress != null)
        .apply {
            if (shippingAddress != null) {
                put("shippingAddressParameters", shippingAddressParameters(shippingAddress))
            }
        }
        .put("shippingOptionRequired", shippingOptionsEnabled)
        .apply {
            if (shippingOptionsEnabled) {
                put("shippingOptionParameters", shippingOptionParameters(transaction))
            }
        }
        .apply {
            // Compose every active feature's callback intents into one array. Both
            // shipping intents need shippingOptionsEnabled, since every recompute
            // resolves a selected shipping option and would otherwise always reject.
            val intents = buildList {
                if (config.googlePayShipping != null && shippingAddress != null && shippingOptionsEnabled) {
                    add("SHIPPING_ADDRESS")
                }
                if (config.googlePayShipping != null && shippingOptionsEnabled) add("SHIPPING_OPTION")
                if (config.googlePayAuthorization != null) add("PAYMENT_AUTHORIZATION")
            }
            if (intents.isNotEmpty()) put("callbackIntents", JSONArray(intents))
        }
        .toString()
}
