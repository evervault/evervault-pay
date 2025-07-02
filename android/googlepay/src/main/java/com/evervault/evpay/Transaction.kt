package com.evervault.googlepay

data class Transaction(val country: String, val currency: String, val lineItems: Array<LineItem>) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false

        other as Transaction

        if (country != other.country) return false
        if (currency != other.currency) return false
        if (!lineItems.contentEquals(other.lineItems)) return false

        return true
    }

    override fun hashCode(): Int {
        var result = country.hashCode()
        result = 31 * result + currency.hashCode()
        result = 31 * result + lineItems.contentHashCode()
        return result
    }
}
