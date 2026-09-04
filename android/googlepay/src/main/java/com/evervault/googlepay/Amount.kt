package com.evervault.googlepay

import java.math.BigDecimal
import java.util.Currency

private const val MAX_FRACTION_DIGITS = 2

// Google documents totalPrice as 0 or exactly 2 fraction digits, but the client
// enforces `-?[0-9]*(\.[0-9][0-9]?)?`, so one digit is fine too. Only the
// two-digit ceiling is real, and it bites once the sheet is already open:
// statusCode 10 with an empty message on Android, OR_BIBED_06 on web. Checking
// here turns that into something an integrator can act on.
// https://developers.google.com/pay/api/android/reference/request-objects#TransactionInfo
private val DECIMAL_FORMAT = Regex("^[0-9]+(\\.[0-9][0-9]?)?$")

/**
 * An amount to show in the Google Pay sheet, either as a decimal string in the
 * currency's major units or as a count of its minor units. Minor units are
 * resolved against the transaction's currency when the request is built.
 *
 * Google Pay carries two fraction digits, so a three-decimal currency (KWD, BHD,
 * OMR, JOD, TND) only reaches hundredths of a major unit: 1.000 KWD is fine,
 * 1.005 KWD is rejected rather than rounded to a different amount.
 */
sealed class Amount {
    private data class Decimal(val value: String) : Amount()

    private data class MinorUnits(val value: Long) : Amount()

    /**
     * This amount as a decimal string in [currency]'s major units.
     * Public so a [GooglePayShippingHandler] can read it to compute a new total.
     * `Amount` has no arithmetic of its own.
     */
    fun format(currency: String): String =
        when (this) {
            is Decimal -> value
            is MinorUnits -> formatMinorUnits(value, currency)
        }

    companion object {
        /** e.g. `Amount("54.99")`, or `Amount("5499")` for a zero-decimal currency. */
        operator fun invoke(amount: String): Amount {
            require(DECIMAL_FORMAT.matches(amount)) {
                "Amount must be a positive decimal number with at most " +
                    "$MAX_FRACTION_DIGITS fraction digits, got \"$amount\""
            }
            return Decimal(amount)
        }

        /** e.g. `Amount.ofMinorUnits(5499)` for 54.99 USD, or 5499 JPY. */
        fun ofMinorUnits(minorUnits: Long): Amount {
            require(minorUnits >= 0) { "Amount must not be negative, got $minorUnits" }
            return MinorUnits(minorUnits)
        }

        private fun formatMinorUnits(minorUnits: Long, currency: String): String {
            val amount = BigDecimal.valueOf(minorUnits).movePointLeft(fractionDigits(currency))
            return try {
                // No rounding mode, so this throws rather than quietly charging
                // a different amount than the one asked for.
                amount.setScale(minOf(amount.scale(), MAX_FRACTION_DIGITS)).toPlainString()
            } catch (e: ArithmeticException) {
                throw IllegalArgumentException(
                    "Google Pay carries $MAX_FRACTION_DIGITS fraction digits, so " +
                        "$amount $currency cannot be represented exactly.",
                    e
                )
            }
        }

        private fun fractionDigits(currency: String): Int {
            val digits =
                try {
                    Currency.getInstance(currency).defaultFractionDigits
                } catch (e: IllegalArgumentException) {
                    throw IllegalArgumentException("Unknown currency \"$currency\"", e)
                }
            // -1 for pseudo-currencies such as XAU.
            require(digits >= 0) { "Currency \"$currency\" has no minor unit" }
            return digits
        }
    }
}
