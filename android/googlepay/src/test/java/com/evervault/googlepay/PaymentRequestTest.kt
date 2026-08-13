package com.evervault.googlepay

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class PaymentRequestTest {
    private val config = Config(appId = "app_123", merchantId = "merchant_123")

    private val transaction = Transaction(
        country = "IE",
        currency = "EUR",
        total = Amount("54.99"),
        lineItems = arrayOf(LineItem("Shell Jacket", Amount("50.00")))
    )

    @Test
    fun `builds a request from config and transaction alone`() {
        val json = JSONObject(buildPaymentRequestJson(config, transaction, "Test Merchant"))

        assertEquals(2, json.getInt("apiVersion"))

        val info = json.getJSONObject("transactionInfo")
        assertEquals("54.99", info.getString("totalPrice"))
        assertEquals("EUR", info.getString("currencyCode"))
        assertEquals("IE", info.getString("countryCode"))
        assertEquals("Test Merchant", json.getJSONObject("merchantInfo").getString("merchantName"))

        val tokenization = json.getJSONArray("allowedPaymentMethods")
            .getJSONObject(0)
            .getJSONObject("tokenizationSpecification")
            .getJSONObject("parameters")
        assertEquals("evervault", tokenization.getString("gateway"))
        assertEquals("merchant_123", tokenization.getString("gatewayMerchantId"))
    }

    @Test
    fun `isReadyToPayRequest does not inherit state from an earlier payment request`() {
        buildPaymentRequestJson(config, transaction, "Test Merchant")

        val request = isReadyToPayRequest(config)!!

        assertFalse(request.has("transactionInfo"))
        assertFalse(request.has("merchantInfo"))
    }
}
