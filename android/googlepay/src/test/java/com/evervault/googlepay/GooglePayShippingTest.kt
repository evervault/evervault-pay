package com.evervault.googlepay

import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class TestShippingHandler : GooglePayShippingHandler {
    override suspend fun recompute(
        request: GooglePayShippingUpdateRequest,
    ): GooglePayShippingUpdateResult = GooglePayShippingUpdateResult.Accept(
        lineItems = request.transaction.lineItems.toList(),
        total = request.transaction.total,
    )
}

class GooglePayShippingTest {
    private val transaction = Transaction(
        country = "IE",
        currency = "EUR",
        total = Amount("54.99"),
        lineItems = arrayOf(LineItem("Shell Jacket", Amount("50.00"))),
        shippingOptions = listOf(
            ShippingOption("standard", "Standard", Amount("5.00")),
            ShippingOption("express", "Express", Amount("15.00")),
        ),
        defaultShippingOptionId = "standard",
    )

    @After
    fun tearDown() {
        GooglePayShippingStateStore.clear()
    }

    @Test
    fun `acceptance returns updated totals to Google Pay`() {
        val result = shippingUpdate(
            GooglePayShippingUpdateResult.Accept(
                lineItems = listOf(
                    LineItem("Shell Jacket", Amount("50.00")),
                    LineItem("Standard", Amount("5.00")),
                ),
                total = Amount("55.00"),
            ),
            transaction,
            "Test Merchant",
        )

        val info = JSONObject(result.toJson()).getJSONObject("newTransactionInfo")
        assertEquals("55.00", info.getString("totalPrice"))
        assertEquals("EUR", info.getString("currencyCode"))
        assertEquals(2, info.getJSONArray("displayItems").length())
        assertEquals("Standard", info.getJSONArray("displayItems").getJSONObject(1).getString("label"))
    }

    @Test
    fun `acceptance keeps the original line items when omitted`() {
        val result = shippingUpdate(
            GooglePayShippingUpdateResult.Accept(total = Amount("55.00")),
            transaction,
            "Test Merchant",
        )

        val displayItems = JSONObject(result.toJson())
            .getJSONObject("newTransactionInfo")
            .getJSONArray("displayItems")

        assertEquals(1, displayItems.length())
        assertEquals("Shell Jacket", displayItems.getJSONObject(0).getString("label"))
    }

    @Test
    fun `acceptance keeps the original total when omitted`() {
        val result = shippingUpdate(
            GooglePayShippingUpdateResult.Accept(
                lineItems = listOf(LineItem("Shell Jacket", Amount("50.00"))),
            ),
            transaction,
            "Test Merchant",
        )

        val info = JSONObject(result.toJson()).getJSONObject("newTransactionInfo")
        assertEquals("54.99", info.getString("totalPrice"))
    }

    @Test
    fun `acceptance with nothing set is a no-op`() {
        val result = shippingUpdate(GooglePayShippingUpdateResult.Accept(), transaction, "Test Merchant")

        val info = JSONObject(result.toJson()).getJSONObject("newTransactionInfo")
        assertEquals("54.99", info.getString("totalPrice"))
        assertEquals(1, info.getJSONArray("displayItems").length())
    }

    @Test
    fun `acceptance preserves each line item's original type`() {
        val result = shippingUpdate(
            GooglePayShippingUpdateResult.Accept(
                lineItems = listOf(
                    LineItem("Shell Jacket", Amount("50.00"), LineItemType.LINE_ITEM),
                    LineItem("Discount", Amount("5.00"), LineItemType.DISCOUNT),
                    LineItem("Tax", Amount("2.00"), LineItemType.TAX),
                    LineItem("Subtotal", Amount("47.00"), LineItemType.SUBTOTAL),
                    LineItem("Standard", Amount("5.00"), LineItemType.SHIPPING_OPTION),
                ),
                total = Amount("54.00"),
            ),
            transaction,
            "Test Merchant",
        )

        val displayItems = JSONObject(result.toJson())
            .getJSONObject("newTransactionInfo")
            .getJSONArray("displayItems")

        assertEquals("LINE_ITEM", displayItems.getJSONObject(0).getString("type"))
        assertEquals("DISCOUNT", displayItems.getJSONObject(1).getString("type"))
        assertEquals("TAX", displayItems.getJSONObject(2).getString("type"))
        assertEquals("SUBTOTAL", displayItems.getJSONObject(3).getString("type"))
        assertEquals("SHIPPING_OPTION", displayItems.getJSONObject(4).getString("type"))
    }

    @Test
    fun `acceptance can only update totals, not replace the shipping option list`() {
        val result = shippingUpdate(
            GooglePayShippingUpdateResult.Accept(lineItems = transaction.lineItems.toList(), total = transaction.total),
            transaction,
            "Test Merchant",
        )

        assertFalse(JSONObject(result.toJson()).has("newShippingOptionParameters"))
    }

    @Test
    fun `acceptance emits newShippingOptionParameters when replacing the shipping option list`() {
        val pickup = ShippingOption("pickup", "Local Pickup", Amount("0.00"))
        val replaced = transaction.copy(shippingOptions = listOf(pickup), defaultShippingOptionId = "pickup")

        val result = shippingUpdate(
            GooglePayShippingUpdateResult.Accept(shippingOptions = listOf(pickup), defaultShippingOptionId = "pickup"),
            replaced,
            "Test Merchant",
        )

        val params = JSONObject(result.toJson()).getJSONObject("newShippingOptionParameters")
        assertEquals(1, params.getJSONArray("shippingOptions").length())
        assertEquals("pickup", params.getJSONArray("shippingOptions").getJSONObject(0).getString("id"))
        assertEquals("pickup", params.getString("defaultSelectedOptionId"))
    }

    @Test
    fun `rejection returns the merchant error to Google Pay`() {
        val result = shippingUpdate(
            GooglePayShippingUpdateResult.Reject(
                message = "We don't ship there",
                intent = GooglePayShippingIntent.ShippingAddress,
                reason = GooglePayShippingErrorReason.ShippingAddressUnserviceable,
            ),
            transaction,
            "Test Merchant",
        )

        val error = JSONObject(result.toJson()).getJSONObject("error")
        assertEquals("We don't ship there", error.getString("message"))
        assertEquals("SHIPPING_ADDRESS_UNSERVICEABLE", error.getString("reason"))
        assertEquals("SHIPPING_ADDRESS", error.getString("intent"))
    }

    @Test
    fun `shippingError builds a typed Google Pay error`() {
        val result = shippingError(
            "Select a shipping option to continue",
            GooglePayShippingIntent.ShippingOption,
            GooglePayShippingErrorReason.ShippingOptionInvalid,
        )

        val error = JSONObject(result.toJson()).getJSONObject("error")
        assertEquals("SHIPPING_OPTION_INVALID", error.getString("reason"))
        assertEquals("SHIPPING_OPTION", error.getString("intent"))
    }

    @Test
    fun `shippingError defaults to OTHER_ERROR`() {
        val result = shippingError("Something went wrong", GooglePayShippingIntent.ShippingAddress)

        val error = JSONObject(result.toJson()).getJSONObject("error")
        assertEquals("OTHER_ERROR", error.getString("reason"))
    }

    @Test
    fun `shipping config requires a positive timeout`() {
        assertThrows(IllegalArgumentException::class.java) {
            GooglePayShippingConfig(TestShippingHandler::class.java, timeoutMillis = 0L)
        }
    }

    @Test
    fun `accept allows a replacement shipping options list with a matching default`() {
        val accept = GooglePayShippingUpdateResult.Accept(
            shippingOptions = listOf(ShippingOption("pickup", "Local Pickup", Amount("0.00"))),
            defaultShippingOptionId = "pickup",
        )

        assertEquals("pickup", accept.defaultShippingOptionId)
    }

    @Test
    fun `accept's replacement shipping options list must not be empty`() {
        assertThrows(IllegalArgumentException::class.java) {
            GooglePayShippingUpdateResult.Accept(shippingOptions = emptyList())
        }
    }

    @Test
    fun `accept's default shipping option id requires a replacement shipping options list`() {
        assertThrows(IllegalArgumentException::class.java) {
            GooglePayShippingUpdateResult.Accept(defaultShippingOptionId = "pickup")
        }
    }

    @Test
    fun `accept's default shipping option id must match one of the replacement options`() {
        assertThrows(IllegalArgumentException::class.java) {
            GooglePayShippingUpdateResult.Accept(
                shippingOptions = listOf(ShippingOption("pickup", "Local Pickup", Amount("0.00"))),
                defaultShippingOptionId = "standard",
            )
        }
    }

    @Test
    fun `creates a handler from its class name`() {
        val handler = GooglePayShippingCoordinator.createHandler(TestShippingHandler::class.java.name)

        assertEquals(TestShippingHandler::class.java, handler::class.java)
    }

    @Test
    fun `extracts the shipping option trigger from a callback`() {
        val trigger = extractShippingTrigger(JSONObject().put("callbackTrigger", "SHIPPING_OPTION"))

        assertEquals(GooglePayShippingIntent.ShippingOption, trigger)
    }

    @Test
    fun `extracts the shipping address trigger from a callback`() {
        val trigger = extractShippingTrigger(JSONObject().put("callbackTrigger", "SHIPPING_ADDRESS"))

        assertEquals(GooglePayShippingIntent.ShippingAddress, trigger)
    }

    @Test
    fun `treats an initialize callback as a shipping address trigger`() {
        // Google Pay's first callback, before the buyer changes anything - there's no
        // distinct GooglePayShippingIntent case for it, see extractShippingTrigger.
        val trigger = extractShippingTrigger(JSONObject().put("callbackTrigger", "INITIALIZE"))

        assertEquals(GooglePayShippingIntent.ShippingAddress, trigger)
    }

    @Test
    fun `extracts the redacted mid-flow shipping address`() {
        val address = extractIntermediateShippingAddress(
            JSONObject()
                .put("administrativeArea", "Dublin")
                .put("countryCode", "IE")
                .put("locality", "Dublin")
                .put("postalCode", "D01 F5P2"),
        )

        assertEquals("IE", address.countryCode)
        assertEquals("Dublin", address.locality)
        assertEquals("Dublin", address.administrativeArea)
        assertEquals("D01 F5P2", address.postalCode)
        assertNull(address.name)
        assertNull(address.address1)
    }

    @Test
    fun `extracts a redacted mid-flow shipping address missing some fields`() {
        // e.g. a locale with no administrative area to redact in the first place.
        val address = extractIntermediateShippingAddress(
            JSONObject()
                .put("countryCode", "IE")
                .put("postalCode", "D01 F5P2"),
        )

        assertEquals("IE", address.countryCode)
        assertEquals("D01 F5P2", address.postalCode)
        assertNull(address.locality)
        assertNull(address.administrativeArea)
        assertNull(address.name)
        assertNull(address.address1)
    }

    @Test
    fun `state store remembers the transaction and defaults the selected option`() {
        GooglePayShippingStateStore.start(transaction, "Test Merchant")

        val state = GooglePayShippingStateStore.current()

        assertEquals(transaction, state?.transaction)
        assertEquals("Test Merchant", state?.merchantName)
        assertEquals("standard", state?.selectedShippingOptionId)
        assertEquals(transaction, state?.current)
    }

    @Test
    fun `mergedTransaction applies the accepted line items and total`() {
        val accept = GooglePayShippingUpdateResult.Accept(
            lineItems = listOf(LineItem("Shell Jacket", Amount("50.00")), LineItem("Standard", Amount("5.00"))),
            total = Amount("55.00"),
        )

        val merged = mergedTransaction(transaction, accept)

        assertEquals(accept.lineItems, merged.lineItems.toList())
        assertEquals(Amount("55.00"), merged.total)
    }

    @Test
    fun `mergedTransaction keeps the current line items and total when the accept omits them`() {
        val merged = mergedTransaction(transaction, GooglePayShippingUpdateResult.Accept())

        assertEquals(transaction.lineItems.toList(), merged.lineItems.toList())
        assertEquals(transaction.total, merged.total)
    }

    @Test
    fun `mergedTransaction keeps the current shipping options when the accept omits them`() {
        val merged = mergedTransaction(transaction, GooglePayShippingUpdateResult.Accept(), previousSelectionId = "express")

        assertEquals(transaction.shippingOptions, merged.shippingOptions)
        assertEquals(transaction.defaultShippingOptionId, merged.defaultShippingOptionId)
    }

    @Test
    fun `mergedTransaction replaces the shipping options list`() {
        val pickup = ShippingOption("pickup", "Local Pickup", Amount("0.00"))

        val merged = mergedTransaction(
            transaction,
            GooglePayShippingUpdateResult.Accept(shippingOptions = listOf(pickup)),
        )

        assertEquals(listOf(pickup), merged.shippingOptions)
    }

    @Test
    fun `mergedTransaction keeps the buyer's previous selection when it survives the replacement`() {
        val pickup = ShippingOption("pickup", "Local Pickup", Amount("0.00"))

        val merged = mergedTransaction(
            transaction,
            GooglePayShippingUpdateResult.Accept(shippingOptions = listOf(pickup, ShippingOption("express", "Express", Amount("15.00")))),
            previousSelectionId = "express",
        )

        assertEquals("express", merged.defaultShippingOptionId)
    }

    @Test
    fun `mergedTransaction falls back to the accept's default when the previous selection doesn't survive`() {
        val pickup = ShippingOption("pickup", "Local Pickup", Amount("0.00"))
        val courier = ShippingOption("courier", "Courier", Amount("20.00"))

        val merged = mergedTransaction(
            transaction,
            GooglePayShippingUpdateResult.Accept(shippingOptions = listOf(pickup, courier), defaultShippingOptionId = "courier"),
            previousSelectionId = "standard",
        )

        assertEquals("courier", merged.defaultShippingOptionId)
    }

    @Test
    fun `mergedTransaction falls back to the replacement list's first option as a last resort`() {
        val pickup = ShippingOption("pickup", "Local Pickup", Amount("0.00"))
        val courier = ShippingOption("courier", "Courier", Amount("20.00"))

        val merged = mergedTransaction(
            transaction,
            GooglePayShippingUpdateResult.Accept(shippingOptions = listOf(pickup, courier)),
            previousSelectionId = "standard",
        )

        assertEquals("pickup", merged.defaultShippingOptionId)
    }

    @Test
    fun `state store tracks the working transaction snapshot separately from the original`() {
        GooglePayShippingStateStore.start(transaction, "Test Merchant")

        val updated = transaction.copy(total = Amount("99.99"))
        GooglePayShippingStateStore.updateCurrent(updated)

        val state = GooglePayShippingStateStore.current()
        assertEquals(updated, state?.current)
        assertEquals(transaction, state?.transaction)
    }

    @Test
    fun `state store tracks the buyer's selected shipping option`() {
        GooglePayShippingStateStore.start(transaction, "Test Merchant")

        GooglePayShippingStateStore.updateSelectedShippingOptionId("express")

        assertEquals("express", GooglePayShippingStateStore.current()?.selectedShippingOptionId)
    }

    @Test
    fun `clearing the state store drops the in-progress transaction`() {
        GooglePayShippingStateStore.start(transaction, "Test Merchant")

        GooglePayShippingStateStore.clear()

        assertNull(GooglePayShippingStateStore.current())
    }
}
