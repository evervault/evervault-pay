package com.evervault.googlepay

/** A single shipping option offered for a [Transaction], e.g. "Standard" or "Express". */
data class ShippingOption(
    val id: String,
    /**
     * Shown to the buyer exactly as given - Google Pay has no price field of
     * its own for a shipping option, so bake one in yourself if you want it
     * shown, e.g. "Standard: €5.00".
     *
     * A label never updates on its own. To show a different one per
     * destination, replace the whole list via
     * [GooglePayShippingUpdateResult.Accept.shippingOptions], reusing the
     * same `id` with a new label.
     */
    val label: String,
    val amount: Amount,
    val description: String? = null,
)
