package com.evervault.googlepay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class PaymentDataTest {
    @Test
    fun `attaches email returned by Google Pay to the token response`() {
        val response = attachPaymentEmail(
            networkTokenResponse(),
            """{"email":"buyer@example.com"}""",
        )

        assertEquals("buyer@example.com", response.email)
    }

    @Test
    fun `attaches email returned by Google Pay to card response`() {
        val response = attachPaymentEmail(
            cardResponse(),
            """{"email":"buyer@example.com"}""",
        )

        assertEquals("buyer@example.com", response.email)
    }

    @Test
    fun `does not attach email when Google Pay did not return one`() {
        val response = attachPaymentEmail(
            networkTokenResponse(),
            """{"paymentMethodData":{}}""",
        )

        assertNull(response.email)
    }

    @Test
    fun `does not attach blank email returned by Google Pay`() {
        val response = attachPaymentEmail(
            networkTokenResponse(),
            """{"email":""}""",
        )

        assertNull(response.email)
    }

    @Test
    fun `attaches last four and display name from card details to the token response`() {
        val response = attachPaymentCardDisplayDetails(
            networkTokenResponse(),
            """{"paymentMethodData":{"description":"Visa •••• 1111","info":{"cardDetails":"1111"}}}""",
        ) as NetworkTokenResponse

        assertEquals("1111", response.card.lastFour)
        assertEquals("Visa •••• 1111", response.card.displayName)
    }

    @Test
    fun `attaches last four and display name from card details to the card response`() {
        val response = attachPaymentCardDisplayDetails(
            cardResponse(),
            """{"paymentMethodData":{"description":"Visa •••• 1111","info":{"cardDetails":"1111"}}}""",
        ) as CardResponse

        assertEquals("1111", response.card.lastFour)
        assertEquals("Visa •••• 1111", response.card.displayName)
    }

    @Test
    fun `falls back to description for last four when card details are missing`() {
        val response = attachPaymentCardDisplayDetails(
            networkTokenResponse(),
            """{"paymentMethodData":{"description":"Visa •••• 4242"}}""",
        ) as NetworkTokenResponse

        assertEquals("4242", response.card.lastFour)
    }

    @Test
    fun `does not attach card display details when Google Pay did not return any`() {
        val response = attachPaymentCardDisplayDetails(
            networkTokenResponse(),
            """{"paymentMethodData":{}}""",
        ) as NetworkTokenResponse

        assertNull(response.card.lastFour)
        assertNull(response.card.displayName)
    }

    @Test
    fun `attaches assurance details returned by Google Pay`() {
        val response = attachAssuranceDetails(
            networkTokenResponse(),
            """{"paymentMethodData":{"info":{"assuranceDetails":{"accountVerified":true,"cardHolderAuthenticated":true}}}}""",
        )

        assertEquals(
            AssuranceDetails(accountVerified = true, cardHolderAuthenticated = true),
            (response as NetworkTokenResponse).card.assuranceDetails,
        )
    }

    @Test
    fun `attaches assurance details to a card response`() {
        val response = attachAssuranceDetails(
            cardResponse(),
            """{"paymentMethodData":{"info":{"assuranceDetails":{"accountVerified":true,"cardHolderAuthenticated":false}}}}""",
        )

        assertEquals(
            AssuranceDetails(accountVerified = true, cardHolderAuthenticated = false),
            (response as CardResponse).card.assuranceDetails,
        )
    }

    @Test
    fun `does not attach assurance details when Google Pay did not return them`() {
        val response = attachAssuranceDetails(
            networkTokenResponse(),
            """{"paymentMethodData":{"info":{}}}""",
        )

        assertNull((response as NetworkTokenResponse).card.assuranceDetails)
    }

    private fun networkTokenResponse() = NetworkTokenResponse(
        card = GooglePayCard(),
        token = PaymentToken(
            number = "4111111111111111",
            expiry = CardExpiry(month = 1, year = 2030),
            tokenServiceProvider = "TEST",
        ),
        cryptogram = "cryptogram",
        eci = "05",
    )

    private fun cardResponse() = CardResponse(
        card = FpanCardDetails(
            number = "4111111111111111",
            expiry = CardExpiry(month = 1, year = 2030),
        ),
    )
}
