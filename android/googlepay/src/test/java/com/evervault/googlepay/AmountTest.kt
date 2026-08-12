package com.evervault.googlepay

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class AmountTest {
    @Test
    fun `minor units are converted using the currency's exponent`() {
        assertEquals("10.00", Amount.ofMinorUnits(1000).format("USD"))
        assertEquals("19.99", Amount.ofMinorUnits(1999).format("EUR"))
        assertEquals("0.05", Amount.ofMinorUnits(5).format("USD"))
        assertEquals("0.00", Amount.ofMinorUnits(0).format("USD"))
        assertEquals("1000", Amount.ofMinorUnits(1000).format("JPY"))
        assertEquals("5", Amount.ofMinorUnits(5).format("KRW"))
    }

    @Test
    fun `decimal amounts are passed through unchanged`() {
        assertEquals("54.99", Amount("54.99").format("USD"))
        assertEquals("1000", Amount("1000").format("JPY"))
    }

    @Test
    fun `rejects amounts that are not decimal numbers`() {
        assertThrows(IllegalArgumentException::class.java) { Amount("ten") }
        assertThrows(IllegalArgumentException::class.java) { Amount("-1.00") }
        assertThrows(IllegalArgumentException::class.java) { Amount("$1.00") }
        assertThrows(IllegalArgumentException::class.java) { Amount("") }
        assertThrows(IllegalArgumentException::class.java) { Amount.ofMinorUnits(-1) }
    }

    @Test
    fun `rejects decimal amounts with more than two fraction digits`() {
        assertThrows(IllegalArgumentException::class.java) { Amount("54.999") }
        assertThrows(IllegalArgumentException::class.java) { Amount("10.123456") }
        assertThrows(IllegalArgumentException::class.java) { Amount("54.") }
    }

    // The docs say exactly two, but the client accepts one.
    @Test
    fun `accepts a single fraction digit`() {
        assertEquals("54.9", Amount("54.9").format("USD"))
    }

    @Test
    fun `three-decimal currencies are truncated to two fraction digits`() {
        assertEquals("1.00", Amount.ofMinorUnits(1000).format("KWD"))
        assertEquals("1.25", Amount.ofMinorUnits(1250).format("KWD"))
        assertEquals("0.05", Amount.ofMinorUnits(50).format("BHD"))
        assertEquals("12.34", Amount.ofMinorUnits(12340).format("OMR"))
        assertEquals("0.00", Amount.ofMinorUnits(0).format("TND"))
    }

    @Test
    fun `three-decimal amounts that would lose precision are rejected`() {
        for (currency in listOf("KWD", "BHD", "OMR", "JOD", "TND")) {
            assertThrows(IllegalArgumentException::class.java) {
                Amount.ofMinorUnits(1005).format(currency)
            }
        }
        assertThrows(IllegalArgumentException::class.java) {
            Amount.ofMinorUnits(1).format("KWD")
        }
    }

    @Test
    fun `rejects unknown currencies when converting minor units`() {
        assertThrows(IllegalArgumentException::class.java) {
            Amount.ofMinorUnits(1000).format("XYZ")
        }
    }
}
