package com.evervault.googlepay

/**
 * How a display item is labelled in the Google Pay sheet.
 *
 * https://developers.google.com/pay/api/android/reference/request-objects#DisplayItem
 */
enum class LineItemType {
    LINE_ITEM,
    SUBTOTAL,
    TAX,
    DISCOUNT,
    SHIPPING_OPTION,
}

data class LineItem(
    val label: String,
    val amount: Amount,
    val type: LineItemType = LineItemType.LINE_ITEM,
) {
    /** Retains the constructor signature from releases before `type`. */
    constructor(label: String, amount: Amount) : this(
        label = label,
        amount = amount,
        type = LineItemType.LINE_ITEM,
    )
}
