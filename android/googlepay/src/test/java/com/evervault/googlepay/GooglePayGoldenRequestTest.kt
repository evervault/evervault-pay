package com.evervault.googlepay

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class GooglePayGoldenRequestTest {
    private val merchantName = "Test Merchant"
    private val config = Config(appId = "app_123", merchantId = "merchant_123")
    private val transaction = Transaction(
        country = "IE",
        currency = "EUR",
        total = Amount.ofMinorUnits(5499),
        lineItems = arrayOf(LineItem("Shell Jacket", Amount.ofMinorUnits(5000)))
    )

    private fun fixture(name: String): JSONObject {
        val stream = requireNotNull(javaClass.classLoader?.getResourceAsStream("google-pay/$name.json"))
        return stream.bufferedReader().use { JSONObject(it.readText()) }
    }

    private fun comparableRequest(config: Config, transaction: Transaction): JSONObject {
        val request = JSONObject(buildPaymentRequestJson(config, transaction, merchantName))
        val displayItems = request.getJSONObject("transactionInfo").getJSONArray("displayItems")
        for (index in 0 until displayItems.length()) {
            // Android requires this Google Pay Android field. Web does not send it.
            displayItems.getJSONObject(index).remove("status")
        }

        return JSONObject()
            .put("apiVersion", request.getInt("apiVersion"))
            .put("apiVersionMinor", request.getInt("apiVersionMinor"))
            .put("emailRequired", request.getBoolean("emailRequired"))
            .put("allowedPaymentMethods", request.getJSONArray("allowedPaymentMethods"))
            .put("merchantInfo", JSONObject().put("merchantName", merchantName))
            .put("transactionInfo", request.getJSONObject("transactionInfo"))
    }

    private fun canonical(value: Any?): String = when (value) {
        is JSONObject -> value.keys().asSequence().toList().sorted().joinToString(
            prefix = "{", postfix = "}", separator = ","
        ) { key -> "${JSONObject.quote(key)}:${canonical(value.get(key))}" }
        is JSONArray -> (0 until value.length()).joinToString(
            prefix = "[", postfix = "]", separator = ","
        ) { index -> canonical(value.get(index)) }
        JSONObject.NULL -> "null"
        is String -> JSONObject.quote(value)
        else -> value.toString()
    }

    @Test
    fun `matches the Android default request fixture`() {
        assertEquals(canonical(fixture("android-default")), canonical(comparableRequest(config, transaction)))
    }

    @Test
    fun `matches the shared enabled-billing request fixture`() {
        assertEquals(canonical(fixture("enabled-billing")), canonical(comparableRequest(config, transaction)))
    }

    @Test
    fun `matches the configured request fixture`() {
        val actual = comparableRequest(
            config.copy(
                emailRequired = true,
                supportedMethods = listOf(CardAuthMethod.PAN_ONLY),
                supportedNetworks = listOf(CardNetwork.INTERAC),
                billingAddress = BillingAddressConfig.Enabled(BillingAddressFormat.MIN, true)
            ),
            transaction.copy(priceLabel = "Subscription")
        )

        assertEquals(canonical(fixture("custom")), canonical(actual))
    }

    @Test
    fun `omits billing address parameters when billing collection is disabled`() {
        val request = comparableRequest(
            config.copy(billingAddress = BillingAddressConfig.Disabled),
            transaction
        )
        val parameters = request.getJSONArray("allowedPaymentMethods")
            .getJSONObject(0)
            .getJSONObject("parameters")

        assertFalse(parameters.has("billingAddressParameters"))
    }
}
