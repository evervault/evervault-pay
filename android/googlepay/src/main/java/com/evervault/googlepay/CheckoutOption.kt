package com.evervault.googlepay

/**
 * Controls the call to action shown in the Google Pay sheet.
 *
 * `COMPLETE_IMMEDIATE_PURCHASE` shows "Pay now" and commits the buyer, so it is
 * only accepted with [TotalPriceStatus.FINAL].
 *
 * https://developers.google.com/pay/api/android/reference/request-objects#TransactionInfo
 */
enum class CheckoutOption {
    DEFAULT,
    COMPLETE_IMMEDIATE_PURCHASE,
    CONTINUE_TO_REVIEW,
}
