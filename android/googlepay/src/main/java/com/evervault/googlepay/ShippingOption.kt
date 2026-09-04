package com.evervault.googlepay

/** A single shipping option offered for a [Transaction], e.g. "Standard" or "Express". */
data class ShippingOption(
    val id: String,
    /**
     * Shown to the buyer exactly as given - Google Pay has no price field of
     * its own for a shipping option, so bake one in yourself if you want it
     * shown, e.g. "Standard: €5.00".
     *
     * Leave the price out if a [GooglePayShippingHandler] charges this
     * option differently by destination: the label is set once, before the
     * buyer picks a destination, and never updates - a baked-in price would
     * go stale.
     */
    val label: String,
    val amount: Amount,
    val description: String? = null,
)
