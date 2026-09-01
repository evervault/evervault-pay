package com.evervault.googlepay

/** A single shipping option offered for a [Transaction], e.g. "Standard" or "Express". */
data class ShippingOption(
    val id: String,
    val label: String,
    val amount: Amount,
    val description: String? = null,
)
