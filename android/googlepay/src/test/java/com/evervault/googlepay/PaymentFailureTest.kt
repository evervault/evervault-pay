package com.evervault.googlepay

import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class PaymentFailureTest {
    @Test
    fun `classifies a cancelled ApiException as Cancelled`() {
        val state = classifyPaymentFailure(
            ApiException(Status(CommonStatusCodes.CANCELED)),
        )

        assertSame(PaymentState.Cancelled, state)
    }

    @Test
    fun `classifies a non-cancelled ApiException as Error`() {
        val state = classifyPaymentFailure(
            ApiException(Status(CommonStatusCodes.NETWORK_ERROR, "Network unavailable")),
        )

        require(state is PaymentState.Error)
        assertEquals(CommonStatusCodes.NETWORK_ERROR, state.code)
        assertEquals("Network unavailable", state.message)
    }

    @Test
    fun `classifies a non-API exception as an internal Error`() {
        val state = classifyPaymentFailure(IllegalStateException("No payment data"))

        require(state is PaymentState.Error)
        assertEquals(CommonStatusCodes.INTERNAL_ERROR, state.code)
        assertEquals("No payment data", state.message)
    }
}
