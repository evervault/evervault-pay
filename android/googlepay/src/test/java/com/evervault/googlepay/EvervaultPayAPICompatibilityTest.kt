package com.evervault.googlepay

import com.google.android.gms.wallet.PaymentData
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.lang.reflect.Modifier

class EvervaultPayAPICompatibilityTest {
    @Test
    fun callbackFetchCryptogramRemainsAvailable() {
        val method = EvervaultPayAPI::class.java.getDeclaredMethod(
            "fetchCryptogram",
            PaymentData::class.java,
            String::class.java,
            EvervaultPayAPICallback::class.java,
        )

        assertTrue(Modifier.isPublic(method.modifiers))
        assertTrue(method.isAnnotationPresent(Deprecated::class.java))
        assertEquals(Void.TYPE, method.returnType)
    }
}
