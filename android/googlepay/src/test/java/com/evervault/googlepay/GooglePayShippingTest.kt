package com.evervault.googlepay

import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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
    fun `creates a handler from its class name`() {
        val handler = GooglePayShippingCoordinator.createHandler(TestShippingHandler::class.java.name)

        assertEquals(TestShippingHandler::class.java, handler::class.java)
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
    fun `state store remembers the transaction and defaults the selected option`() {
        GooglePayShippingStateStore.start(transaction, "Test Merchant")

        val state = GooglePayShippingStateStore.current()

        assertEquals(transaction, state?.transaction)
        assertEquals("Test Merchant", state?.merchantName)
        assertEquals("standard", state?.selectedShippingOptionId)
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
