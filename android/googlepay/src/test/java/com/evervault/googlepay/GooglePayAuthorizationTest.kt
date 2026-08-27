package com.evervault.googlepay

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test

class TestAuthorizationHandler : GooglePayAuthorizationHandler {
    override suspend fun authorize(
        payment: TokenResponse,
        transaction: Transaction,
    ): GooglePayAuthorizationResult = GooglePayAuthorizationResult.Accept
}

class GooglePayAuthorizationTest {
    @Test
    fun `acceptance returns a Google Pay success result`() {
        val result = authorizationResult(GooglePayAuthorizationResult.Accept)

        assertEquals("SUCCESS", JSONObject(result.toJson()).getString("transactionState"))
    }

    @Test
    fun `rejection returns the merchant error to Google Pay`() {
        val result = authorizationResult(
            GooglePayAuthorizationResult.Reject(
                message = "Your card was declined",
                reason = "PAYMENT_DATA_INVALID",
            ),
        )

        val json = JSONObject(result.toJson())
        val error = json.getJSONObject("error")
        assertEquals("ERROR", json.getString("transactionState"))
        assertEquals("Your card was declined", error.getString("message"))
        assertEquals("PAYMENT_DATA_INVALID", error.getString("reason"))
        assertEquals("PAYMENT_AUTHORIZATION", error.getString("intent"))
    }
}
