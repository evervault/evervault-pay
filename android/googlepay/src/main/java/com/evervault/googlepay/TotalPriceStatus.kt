package com.evervault.googlepay

/**
 * How settled `totalPrice` is. Use [ESTIMATED] when the total can still change
 * (for example before shipping is chosen), [FINAL] when it cannot.
 *
 * https://developers.google.com/pay/api/android/reference/request-objects#TransactionInfo
 */
enum class TotalPriceStatus {
    ESTIMATED,
    FINAL,
}
