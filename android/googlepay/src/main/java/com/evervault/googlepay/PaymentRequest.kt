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
//
// Sent with the initial request, and again as newShippingOptionParameters
// whenever a GooglePayShippingHandler replaces the list - see ShippingOption.label.
internal fun shippingOptionParametersJson(options: List<ShippingOption>, defaultShippingOptionId: String?): JSONObject {
    val parameters = JSONObject()
        .put("shippingOptions", JSONArray(options.map {
            JSONObject()
                .put("id", it.id)
                .put("label", it.label)
                .apply { if (it.description != null) put("description", it.description) }
        }))

    if (defaultShippingOptionId != null) {
        parameters.put("defaultSelectedOptionId", defaultShippingOptionId)
    }

    return parameters
}

private fun shippingOptionParameters(transaction: Transaction): JSONObject =
    shippingOptionParametersJson(transaction.shippingOptions, transaction.defaultShippingOptionId)

// https://developers.google.com/pay/api/android/reference/request-objects#TransactionInfo
internal fun buildPaymentRequestJson(
    config: Config,
    transaction: Transaction,
    merchantName: String
): String {
    require(!(transaction.shippingOptions.isNotEmpty() && config.googlePayShipping == null)) {
        "Config.googlePayShipping is required when Transaction.shippingOptions is set. " +
            "Google Pay reports the buyer's selected option via that callback"
    }
    require(!(config.googlePayShipping != null && transaction.shippingOptions.isEmpty())) {
        "Transaction.shippingOptions is required when Config.googlePayShipping is set. " +
            "Without any options, the callback would never have one to report"
    }

    val shippingOptionsEnabled = transaction.shippingOptions.isNotEmpty()

    // Shipping options need a destination to ship to.
    val shippingAddress = (config.shippingAddress as? ShippingAddressConfig.Enabled)
        ?: if (shippingOptionsEnabled) ShippingAddressConfig.Enabled() else null

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
