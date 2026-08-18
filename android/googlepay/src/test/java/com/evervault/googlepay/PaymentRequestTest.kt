package com.evervault.googlepay

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
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
    fun `retains the pre-emailRequired Config constructor`() {
        assertNotNull(
            Config::class.java.getConstructor(
                String::class.java,
                String::class.java,
                List::class.java,
                List::class.java,
                BillingAddressConfig::class.java,
            )
        )
    }

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

    private fun transactionInfo(transaction: Transaction): JSONObject =
        JSONObject(buildPaymentRequestJson(config, transaction, "Test Merchant"))
            .getJSONObject("transactionInfo")

    @Test
    fun `minor units resolve against the transaction currency`() {
        val info = transactionInfo(
            transaction.copy(
                currency = "USD",
                total = Amount.ofMinorUnits(5499),
                lineItems = arrayOf(LineItem("Shell Jacket", Amount.ofMinorUnits(5000)))
            )
        )

        assertEquals("54.99", info.getString("totalPrice"))
        assertEquals("50.00", info.getJSONArray("displayItems").getJSONObject(0).getString("price"))
    }

    @Test
    fun `minor units in a zero-decimal currency carry no decimal point`() {
        val info = transactionInfo(
            transaction.copy(
                currency = "JPY",
                total = Amount.ofMinorUnits(5499),
                lineItems = arrayOf(LineItem("Shell Jacket", Amount.ofMinorUnits(5000)))
            )
        )

        assertEquals("5499", info.getString("totalPrice"))
        assertEquals("5000", info.getJSONArray("displayItems").getJSONObject(0).getString("price"))
    }

    @Test
    fun `a three-decimal currency is carried to two fraction digits`() {
        val info = transactionInfo(
            transaction.copy(
                currency = "KWD",
                total = Amount.ofMinorUnits(1250),
                lineItems = arrayOf(LineItem("Shell Jacket", Amount.ofMinorUnits(1000)))
            )
        )

        assertEquals("1.25", info.getString("totalPrice"))
        assertEquals("1.00", info.getJSONArray("displayItems").getJSONObject(0).getString("price"))
    }

    @Test
    fun `building a request fails when a three-decimal amount needs the third digit`() {
        assertThrows(IllegalArgumentException::class.java) {
            buildPaymentRequestJson(
                config,
                transaction.copy(currency = "KWD", total = Amount.ofMinorUnits(1005)),
                "Test Merchant"
            )
        }
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
    fun `the price label defaults to Pay plus the merchant name`() {
        assertEquals("Pay Test Merchant", transactionInfo(transaction).getString("totalPriceLabel"))
    }

    @Test
    fun `the default price label follows the merchant name`() {
        val json = JSONObject(buildPaymentRequestJson(config, transaction, "Acme Bikes"))

        assertEquals(
            "Pay Acme Bikes",
            json.getJSONObject("transactionInfo").getString("totalPriceLabel")
        )
    }

    @Test
    fun `the price label is overridable`() {
        val info = transactionInfo(transaction.copy(priceLabel = "Subscription"))

        assertEquals("Subscription", info.getString("totalPriceLabel"))
    }

    @Test
    fun `an empty price label is sent as given`() {
        assertEquals("", transactionInfo(transaction.copy(priceLabel = "")).getString("totalPriceLabel"))
    }

    @Test
    fun `the price label takes part in transaction equality`() {
        assertEquals(transaction, transaction.copy())
        assertNotEquals(transaction, transaction.copy(priceLabel = "Subscription"))
        assertNotEquals(
            transaction.copy(priceLabel = "Subscription"),
            transaction.copy(priceLabel = "Donation")
        )
    }

    @Test
    fun `default card networks match the web SDK exactly`() {
        // The literal web sends when the merchant omits `allowedCardNetworks`.
        // See buildPaymentRequest in evervault-js ui-components/src/GooglePay/utilities.ts.
        val expected = listOf("AMEX", "DISCOVER", "INTERAC", "JCB", "MASTERCARD", "VISA")

        val networks = cardParameters(config).getJSONArray("allowedCardNetworks")

        assertEquals(expected, (0 until networks.length()).map { networks.getString(it) })
    }

    @Test
    fun `every card network the enum offers is allowed by default`() {
        val networks = cardParameters(config).getJSONArray("allowedCardNetworks")

        assertEquals(
            CardNetwork.entries.map { it.name },
            (0 until networks.length()).map { networks.getString(it) }
        )
    }

    @Test
    fun `card networks are configurable`() {
        val networks = cardParameters(config.copy(supportedNetworks = listOf(CardNetwork.INTERAC)))
            .getJSONArray("allowedCardNetworks")

        assertEquals(1, networks.length())
        assertEquals("INTERAC", networks.getString(0))
    }

    @Test
    fun `email is not requested by default`() {
        val json = JSONObject(buildPaymentRequestJson(config, transaction, "Test Merchant"))

        assertTrue(json.has("emailRequired"))
        assertFalse(json.getBoolean("emailRequired"))
    }

    @Test
    fun `email is requested when configured`() {
        val json = JSONObject(
            buildPaymentRequestJson(config.copy(emailRequired = true), transaction, "Test Merchant")
        )

        assertTrue(json.getBoolean("emailRequired"))
    }

    @Test
    fun `isReadyToPayRequest does not carry emailRequired`() {
        val request = isReadyToPayRequest(config.copy(emailRequired = true))!!

        assertFalse(request.has("emailRequired"))
    }

    @Test
    fun `isReadyToPayRequest does not inherit state from an earlier payment request`() {
        buildPaymentRequestJson(config, transaction, "Test Merchant")

        val request = isReadyToPayRequest(config)!!

        assertFalse(request.has("transactionInfo"))
        assertFalse(request.has("merchantInfo"))
    }
}
