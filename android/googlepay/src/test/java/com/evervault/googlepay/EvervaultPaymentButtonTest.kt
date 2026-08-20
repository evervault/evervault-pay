package com.evervault.googlepay

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

class EvervaultPaymentButtonTest {
    @Test
    fun `the default corner radius matches the web SDK`() {
        assertEquals(12.dp, EvervaultPaymentButtonDefaults.Radius)
    }
}
