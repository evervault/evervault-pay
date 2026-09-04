package com.evervault.googlepay

import com.google.gson.GsonBuilder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class GooglePayResponseParityTest {
    private val gson = GsonBuilder()
        .registerTypeAdapter(TokenResponse::class.java, TokenResponseAdapter())
        .create()

    @Test
    fun `retains card constructors from before paymentMethodType`() {
        GooglePayCard::class.java.getConstructor(
            String::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
        )
        FpanCardDetails::class.java.getConstructor(
            String::class.java,
            CardExpiry::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
        )
    }

    @Test
    fun `retains card constructors from before lastFour and displayName`() {
        GooglePayCard::class.java.getConstructor(
            String::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
        )
        FpanCardDetails::class.java.getConstructor(
            String::class.java,
            CardExpiry::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
            String::class.java,
        )
    }

    @Test
    fun `enriches a network token response with every Google Pay field returned on web`() {
        val response = enrich(networkTokenDecryptionResponse, paymentData)
            as NetworkTokenResponse

        assertEquals("visa", response.card.brand)
        assertEquals("credit", response.card.funding)
        assertEquals("credit", response.card.paymentMethodType)
        assertEquals("1111", response.card.lastFour)
        assertEquals("Visa •••• 1111", response.card.displayName)
        assertEquals("4111111111111111", response.token.number)
        assertEquals(12, response.token.expiry.month)
        assertEquals(2030, response.token.expiry.year)
        assertEquals("google", response.token.tokenServiceProvider)
        assertEquals("cryptogram", response.cryptogram)
        assertEquals("05", response.eci)
        assertEquals("message-id", response.messageId)
        assertEquals("2030-12-31T23:59:59Z", response.messageExpiration)
        assertEquals("buyer@example.com", response.email)
        assertNotNull(response.billingAddress)
        assertEquals("Buyer", response.billingAddress?.name)
        assertEquals("D01 F5P2", response.billingAddress?.postalCode)
    }

    @Test
    fun `enriches a card response with every Google Pay field returned on web`() {
        val response = enrich(cardDecryptionResponse, paymentData)
            as CardResponse

        assertEquals("visa", response.card.brand)
        assertEquals("credit", response.card.funding)
        assertEquals("credit", response.card.paymentMethodType)
        assertEquals("1111", response.card.lastFour)
        assertEquals("Visa •••• 1111", response.card.displayName)
        assertEquals("4111111111111111", response.card.number)
        assertEquals(12, response.card.expiry.month)
        assertEquals(2030, response.card.expiry.year)
        assertEquals("message-id", response.messageId)
        assertEquals("2030-12-31T23:59:59Z", response.messageExpiration)
        assertEquals("buyer@example.com", response.email)
        assertNotNull(response.billingAddress)
        assertEquals("Buyer", response.billingAddress?.name)
        assertEquals("D01 F5P2", response.billingAddress?.postalCode)
    }

    @Test
    fun `maps every supported Google Pay funding source`() {
        mapOf(
            "CREDIT" to "credit",
            "DEBIT" to "debit",
            "PREPAID" to "prepaid",
        ).forEach { (fundingSource, paymentMethodType) ->
            val response = enrich(
                networkTokenDecryptionResponse,
                paymentData.replace("\"CREDIT\"", "\"$fundingSource\""),
            ) as NetworkTokenResponse

            assertEquals(paymentMethodType, response.card.paymentMethodType)
        }
    }

    @Test
    fun `does not expose unknown Google Pay funding sources`() {
        val response = enrich(
            networkTokenDecryptionResponse,
            paymentData.replace("\"CREDIT\"", "\"UNKNOWN\""),
        ) as NetworkTokenResponse

        assertEquals(null, response.card.paymentMethodType)
    }

    private fun enrich(decryptionResponse: String, paymentInformation: String): TokenResponse {
        val response = gson.fromJson(decryptionResponse, TokenResponse::class.java)
        extractPaymentBillingAddress(paymentInformation)?.let { response.billingAddress = it }
        val responseWithMethodType = attachPaymentMethodType(
            attachPaymentEmail(response, paymentInformation),
            paymentInformation,
        )
        return attachPaymentCardDisplayDetails(responseWithMethodType, paymentInformation)
    }

    private companion object {
        const val networkTokenDecryptionResponse = """
            {
              "card": {"brand": "visa", "funding": "credit"},
              "token": {
                "number": "4111111111111111",
                "expiry": {"month": 12, "year": 2030},
                "tokenServiceProvider": "google"
              },
              "cryptogram": "cryptogram",
              "eci": "05",
              "messageId": "message-id",
              "messageExpiration": "2030-12-31T23:59:59Z"
            }
        """

        const val cardDecryptionResponse = """
            {
              "card": {
                "number": "4111111111111111",
                "expiry": {"month": 12, "year": 2030},
                "brand": "visa",
                "funding": "credit"
              },
              "messageId": "message-id",
              "messageExpiration": "2030-12-31T23:59:59Z"
            }
        """

        const val paymentData = """
            {
              "email": "buyer@example.com",
              "paymentMethodData": {
                "description": "Visa •••• 1111",
                "info": {
                  "cardDetails": "1111",
                  "cardFundingSource": "CREDIT",
                  "billingAddress": {
                    "name": "Buyer",
                    "postalCode": "D01 F5P2",
                    "countryCode": "IE",
                    "address1": "1 Example Street",
                    "locality": "Dublin"
                  }
                }
              }
            }
        """
    }
}
