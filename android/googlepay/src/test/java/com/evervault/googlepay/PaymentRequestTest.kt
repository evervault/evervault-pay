package com.evervault.googlepay

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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

    private fun cardParameters(config: Config): JSONObject =
        JSONObject(buildPaymentRequestJson(config, transaction, "Test Merchant"))
            .getJSONArray("allowedPaymentMethods")
            .getJSONObject(0)
            .getJSONObject("parameters")

    @Test
    fun `billing address defaults to FULL without a phone number`() {
        val parameters = cardParameters(config)

        assertTrue(parameters.getBoolean("billingAddressRequired"))
        val billing = parameters.getJSONObject("billingAddressParameters")
        assertEquals("FULL", billing.getString("format"))
        assertFalse(billing.getBoolean("phoneNumberRequired"))
    }

    @Test
    fun `billing address is not collected when disabled`() {
        val parameters = cardParameters(config.copy(billingAddress = BillingAddressConfig.Disabled))

        assertFalse(parameters.getBoolean("billingAddressRequired"))
        assertFalse(parameters.has("billingAddressParameters"))
    }

    @Test
    fun `billing address format and phone number are configurable`() {
        val parameters = cardParameters(
            config.copy(
                billingAddress = BillingAddressConfig.Enabled(
                    format = BillingAddressFormat.MIN,
                    phoneNumber = true
                )
            )
        )

        assertTrue(parameters.getBoolean("billingAddressRequired"))
        val billing = parameters.getJSONObject("billingAddressParameters")
        assertEquals("MIN", billing.getString("format"))
        assertTrue(billing.getBoolean("phoneNumberRequired"))
    }

    @Test
    fun `isReadyToPayRequest does not inherit state from an earlier payment request`() {
        buildPaymentRequestJson(config, transaction, "Test Merchant")

        val request = isReadyToPayRequest(config)!!

        assertFalse(request.has("transactionInfo"))
        assertFalse(request.has("merchantInfo"))
    }
}
