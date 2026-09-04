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
    fun `retains the pre-shippingOptions Transaction constructor`() {
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
    fun `retains the pre-shippingAddress Config constructor`() {
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

    private val shippableTransaction = transaction.copy(
        shippingOptions = listOf(
            ShippingOption("standard", "Standard", Amount("5.00")),
            ShippingOption("express", "Express", Amount("15.00")),
        ),
        defaultShippingOptionId = "standard",
    )

    @Test
    fun `defaultShippingOptionId must match one of the shipping options`() {
        assertThrows(IllegalArgumentException::class.java) {
            transaction.copy(
                shippingOptions = listOf(ShippingOption("standard", "Standard", Amount("5.00"))),
                defaultShippingOptionId = "express",
            )
        }
    }

    @Test
    fun `shipping options take part in transaction equality`() {
        assertEquals(shippableTransaction, shippableTransaction.copy())
        assertNotEquals(transaction, shippableTransaction)
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
    fun `shipping address is not collected by default`() {
        val json = JSONObject(buildPaymentRequestJson(config, transaction, "Test Merchant"))

        assertFalse(json.getBoolean("shippingAddressRequired"))
        assertFalse(json.has("shippingAddressParameters"))
    }

    @Test
    fun `shipping address requests allowed countries and a phone number when configured`() {
        val json = JSONObject(
            buildPaymentRequestJson(
                config.copy(
                    shippingAddress = ShippingAddressConfig.Enabled(
                        allowedCountryCodes = listOf("US", "CA"),
                        phoneNumberRequired = true,
                    ),
                ),
                transaction,
                "Test Merchant",
            )
        )

        assertTrue(json.getBoolean("shippingAddressRequired"))
        val parameters = json.getJSONObject("shippingAddressParameters")
        assertTrue(parameters.getBoolean("phoneNumberRequired"))
        val countries = parameters.getJSONArray("allowedCountryCodes")
        assertEquals(listOf("US", "CA"), (0 until countries.length()).map { countries.getString(it) })
    }

    @Test
    fun `shipping address defaults omit allowedCountryCodes and require no phone number`() {
        val json = JSONObject(
            buildPaymentRequestJson(
                config.copy(shippingAddress = ShippingAddressConfig.Enabled()),
                transaction,
                "Test Merchant",
            )
        )

        val parameters = json.getJSONObject("shippingAddressParameters")
        assertFalse(parameters.getBoolean("phoneNumberRequired"))
        assertFalse(parameters.has("allowedCountryCodes"))
    }

    @Test
    fun `shipping is required in the sheet without firing a callback when no handler is configured`() {
        val json = JSONObject(
            buildPaymentRequestJson(
                config.copy(shippingAddress = ShippingAddressConfig.Enabled()),
                shippableTransaction,
                "Test Merchant",
            )
        )

        assertTrue(json.getBoolean("shippingAddressRequired"))
        assertTrue(json.getBoolean("shippingOptionRequired"))
        assertFalse(json.has("callbackIntents"))
    }

    @Test
    fun `shipping option is not requested without shippingOptions on the transaction`() {
        val json = JSONObject(buildPaymentRequestJson(config, transaction, "Test Merchant"))

        assertFalse(json.getBoolean("shippingOptionRequired"))
        assertFalse(json.has("shippingOptionParameters"))
    }

    @Test
    fun `shipping option parameters list every option and the default selection`() {
        val json = JSONObject(buildPaymentRequestJson(config, shippableTransaction, "Test Merchant"))

        assertTrue(json.getBoolean("shippingOptionRequired"))
        val parameters = json.getJSONObject("shippingOptionParameters")
        assertEquals("standard", parameters.getString("defaultSelectedOptionId"))
        val options = parameters.getJSONArray("shippingOptions")
        assertEquals(2, options.length())
        assertEquals("standard", options.getJSONObject(0).getString("id"))
        assertEquals("Standard", options.getJSONObject(0).getString("label"))
        assertFalse(options.getJSONObject(0).has("description"))
    }

    @Test
    fun `shipping option description is included only when given`() {
        val json = JSONObject(
            buildPaymentRequestJson(
                config,
                shippableTransaction.copy(
                    shippingOptions = listOf(
                        ShippingOption("standard", "Standard", Amount("5.00"), "Arrives in 5-7 days"),
                    ),
                    defaultShippingOptionId = "standard",
                ),
                "Test Merchant",
            )
        )

        val option = json.getJSONObject("shippingOptionParameters")
            .getJSONArray("shippingOptions")
            .getJSONObject(0)
        assertEquals("Arrives in 5-7 days", option.getString("description"))
    }

    @Test
    fun `shipping option label is sent exactly as given, since Google Pay has no price field of its own`() {
        val json = JSONObject(
            buildPaymentRequestJson(
                config,
                shippableTransaction.copy(
                    shippingOptions = listOf(ShippingOption("express", "Express: €15.00", Amount("15.00"))),
                    defaultShippingOptionId = "express",
                ),
                "Test Merchant",
            )
        )

        val label = json.getJSONObject("shippingOptionParameters")
            .getJSONArray("shippingOptions")
            .getJSONObject(0)
            .getString("label")
        assertEquals("Express: €15.00", label)
    }

    @Test
    fun `shipping callbacks compose with inline authorization`() {
        val json = JSONObject(
            buildPaymentRequestJson(
                config.copy(
                    shippingAddress = ShippingAddressConfig.Enabled(),
                    googlePayShipping = GooglePayShippingConfig(TestShippingHandler::class.java),
                    googlePayAuthorization = GooglePayAuthorizationConfig(TestAuthorizationHandler::class.java),
                ),
                shippableTransaction,
                "Test Merchant",
            )
        )

        val intents = json.getJSONArray("callbackIntents")
        assertEquals(
            listOf("SHIPPING_ADDRESS", "SHIPPING_OPTION", "PAYMENT_AUTHORIZATION"),
            (0 until intents.length()).map { intents.getString(it) },
        )
    }

    @Test
    fun `shipping option callback fires even without shipping address collection`() {
        val json = JSONObject(
            buildPaymentRequestJson(
                config.copy(googlePayShipping = GooglePayShippingConfig(TestShippingHandler::class.java)),
                shippableTransaction,
                "Test Merchant",
            )
        )

        val intents = json.getJSONArray("callbackIntents")
        assertEquals(listOf("SHIPPING_OPTION"), (0 until intents.length()).map { intents.getString(it) })
    }

    @Test
    fun `shipping callbacks do not fire without shipping options on the transaction`() {
        // Every recompute resolves a selected shipping option (see
        // GooglePayShippingCoordinator.recompute), so a callback would reject every
        // time without shipping options to resolve against - even an address-only one.
        val json = JSONObject(
            buildPaymentRequestJson(
                config.copy(
                    shippingAddress = ShippingAddressConfig.Enabled(),
                    googlePayShipping = GooglePayShippingConfig(TestShippingHandler::class.java),
                ),
                transaction,
                "Test Merchant",
            )
        )

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
