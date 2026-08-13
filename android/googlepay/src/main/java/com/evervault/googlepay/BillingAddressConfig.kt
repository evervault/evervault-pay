package com.evervault.googlepay

enum class BillingAddressFormat { MIN, FULL }

sealed interface BillingAddressConfig {
    data object Disabled : BillingAddressConfig

    data class Enabled(
        val format: BillingAddressFormat = BillingAddressFormat.FULL,
        val phoneNumber: Boolean = false
    ) : BillingAddressConfig
}
