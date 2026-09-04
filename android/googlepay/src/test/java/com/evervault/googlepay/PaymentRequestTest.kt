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
    fun `retains the pre-config-batch Config constructor`() {
        assertNotNull(
            Config::class.java.getConstructor(
                String::class.java,
                String::class.java,
                List::class.java,
                List::class.java,
                BillingAddressConfig::class.java,
                Boolean::class.javaPrimitiveType,
                GooglePayAuthorizationConfig::class.java,
            )
        )
    }

    @Test
    fun `retains the pre-priceLabel Transaction constructor`() {
        assertNotNull(
            Transaction::class.java.getConstructor(
                String::class.java,
                String::class.java,
                Amount::class.java,
                Array<LineItem>::class.java,
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
    fun `billing address is not collected by default`() {
        val parameters = cardParameters(config)

        assertFalse(parameters.getBoolean("billingAddressRequired"))
        assertFalse(parameters.has("billingAddressParameters"))
    }

    @Test
    fun `an enabled billing address defaults to FULL without a phone number`() {
        val parameters = cardParameters(config.copy(billingAddress = BillingAddressConfig.Enabled()))

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
    fun `display item types default to LINE_ITEM and are overridable`() {
        val info = transactionInfo(
            transaction.copy(
                lineItems = arrayOf(
                    LineItem("Shell Jacket", Amount("50.00")),
                    LineItem("Subtotal", Amount("50.00"), LineItemType.SUBTOTAL),
                    LineItem("VAT", Amount("4.99"), LineItemType.TAX),
                    LineItem("Promo", Amount("1.00"), LineItemType.DISCOUNT),
                    LineItem("Delivery", Amount("0.00"), LineItemType.SHIPPING_OPTION),
                )
            )
        )

        val items = info.getJSONArray("displayItems")
        assertEquals("LINE_ITEM", items.getJSONObject(0).getString("type"))
        assertEquals("SUBTOTAL", items.getJSONObject(1).getString("type"))
        assertEquals("TAX", items.getJSONObject(2).getString("type"))
        assertEquals("DISCOUNT", items.getJSONObject(3).getString("type"))
        assertEquals("SHIPPING_OPTION", items.getJSONObject(4).getString("type"))
    }

    @Test
    fun `retains the pre-type LineItem constructor`() {
        assertNotNull(
            LineItem::class.java.getConstructor(String::class.java, Amount::class.java)
        )
    }

    @Test
    fun `the total price status defaults to FINAL and is overridable`() {
        assertEquals("FINAL", transactionInfo(transaction).getString("totalPriceStatus"))
        assertEquals(
            "ESTIMATED",
            transactionInfo(transaction.copy(totalPriceStatus = TotalPriceStatus.ESTIMATED))
                .getString("totalPriceStatus")
        )
    }

    @Test
    fun `the checkout option and transaction id are omitted unless set`() {
        val info = transactionInfo(transaction)

        assertFalse(info.has("checkoutOption"))
        assertFalse(info.has("transactionId"))
    }

    @Test
    fun `the checkout option and transaction id are sent when set`() {
        val info = transactionInfo(
            transaction.copy(
                checkoutOption = CheckoutOption.COMPLETE_IMMEDIATE_PURCHASE,
                transactionId = "txn_123",
            )
        )

        assertEquals("COMPLETE_IMMEDIATE_PURCHASE", info.getString("checkoutOption"))
        assertEquals("txn_123", info.getString("transactionId"))
    }

    @Test
    fun `an immediate purchase checkout option requires a final total`() {
        assertThrows(IllegalArgumentException::class.java) {
            transaction.copy(
                totalPriceStatus = TotalPriceStatus.ESTIMATED,
                checkoutOption = CheckoutOption.COMPLETE_IMMEDIATE_PURCHASE,
            )
        }
    }

    @Test
    fun `retains the pre-totalPriceStatus Transaction constructor`() {
        assertNotNull(
            Transaction::class.java.getConstructor(
                String::class.java,
                String::class.java,
                Amount::class.java,
                Array<LineItem>::class.java,
                String::class.java,
            )
        )
    }

    @Test
    fun `prepaid and credit cards are allowed by default and can be refused`() {
        val default = cardParameters(config)
        assertFalse(default.has("allowPrepaidCards"))
        assertFalse(default.has("allowCreditCards"))

        val restricted = cardParameters(
            config.copy(allowPrepaidCards = false, allowCreditCards = false)
        )
        assertFalse(restricted.getBoolean("allowPrepaidCards"))
        assertFalse(restricted.getBoolean("allowCreditCards"))
    }

    @Test
    fun `assurance details are not requested by default`() {
        assertFalse(cardParameters(config).has("assuranceDetailsRequired"))
        assertTrue(
            cardParameters(config.copy(assuranceDetailsRequired = true))
                .getBoolean("assuranceDetailsRequired")
        )
    }

    @Test
    fun `isReadyToPay carries the existing payment method requirement`() {
        assertFalse(isReadyToPayRequest(config)!!.has("existingPaymentMethodRequired"))
        assertTrue(
            isReadyToPayRequest(config.copy(existingPaymentMethodRequired = true))!!
                .getBoolean("existingPaymentMethodRequired")
        )
    }

    @Test
    fun `the price label takes part in transaction equality`() {
        assertEquals(transaction, transaction.copy())
        assertNotEquals(transaction, transaction.copy(priceLabel = "Subscription"))
        assertNotEquals(
            transaction.copy(priceLabel = "Subscription"),
            transaction.copy(priceLabel = "Donation")
        )
        assertNotEquals(transaction, transaction.copy(transactionId = "txn_123"))
        assertNotEquals(
            transaction,
            transaction.copy(totalPriceStatus = TotalPriceStatus.ESTIMATED)
        )
        assertNotEquals(
            transaction,
            transaction.copy(checkoutOption = CheckoutOption.COMPLETE_IMMEDIATE_PURCHASE)
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
    fun `inline authorization requests the Google Pay callback`() {
        val authorization = config.copy(
            googlePayAuthorization = GooglePayAuthorizationConfig(TestAuthorizationHandler::class.java),
        )

        val json = JSONObject(buildPaymentRequestJson(authorization, transaction, "Test Merchant"))

        assertEquals(
            "PAYMENT_AUTHORIZATION",
            json.getJSONArray("callbackIntents").getString(0),
        )
    }

    @Test
    fun `payment requests omit callbacks without inline authorization`() {
        val json = JSONObject(buildPaymentRequestJson(config, transaction, "Test Merchant"))

        assertFalse(json.has("callbackIntents"))
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
