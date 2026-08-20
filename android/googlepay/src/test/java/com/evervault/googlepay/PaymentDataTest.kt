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
