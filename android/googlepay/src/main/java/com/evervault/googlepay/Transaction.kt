package com.evervault.googlepay

data class Transaction(
    val country: String,
    val currency: String,
    val total: Amount,
    val lineItems: Array<LineItem>,
    val priceLabel: String? = null,
    val totalPriceStatus: TotalPriceStatus = TotalPriceStatus.FINAL,
    val checkoutOption: CheckoutOption? = null,
    /** A unique identifier for this Google Pay facilitation attempt. */
    val transactionId: String? = null,
) {
    init {
        require(
            checkoutOption != CheckoutOption.COMPLETE_IMMEDIATE_PURCHASE ||
                totalPriceStatus == TotalPriceStatus.FINAL
        ) {
            "checkoutOption COMPLETE_IMMEDIATE_PURCHASE requires a FINAL totalPriceStatus, " +
                "got $totalPriceStatus"
        }
    }

    /** Retains the constructor signature from releases before `priceLabel`. */
    constructor(
        country: String,
        currency: String,
        total: Amount,
        lineItems: Array<LineItem>,
    ) : this(
        country = country,
        currency = currency,
        total = total,
        lineItems = lineItems,
        priceLabel = null,
    )

    /** Retains the constructor signature from releases before `totalPriceStatus`. */
    constructor(
        country: String,
        currency: String,
        total: Amount,
        lineItems: Array<LineItem>,
        priceLabel: String?,
    ) : this(
        country = country,
        currency = currency,
        total = total,
        lineItems = lineItems,
        priceLabel = priceLabel,
        totalPriceStatus = TotalPriceStatus.FINAL,
        checkoutOption = null,
        transactionId = null,
    )

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as Transaction

        if (country != other.country) return false
        if (currency != other.currency) return false
        if (!lineItems.contentEquals(other.lineItems)) return false
        if (total != other.total) return false
        if (priceLabel != other.priceLabel) return false
        if (totalPriceStatus != other.totalPriceStatus) return false
        if (checkoutOption != other.checkoutOption) return false
        if (transactionId != other.transactionId) return false
        return true
    }

    override fun hashCode(): Int {
        var result = country.hashCode()
        result = 31 * result + currency.hashCode()
        result = 31 * result + lineItems.contentHashCode()
        result = 31 * result + total.hashCode()
        result = 31 * result + priceLabel.hashCode()
        result = 31 * result + totalPriceStatus.hashCode()
        result = 31 * result + checkoutOption.hashCode()
        result = 31 * result + transactionId.hashCode()
        return result
    }
}
