package com.evervault.googlepay

sealed interface ShippingAddressConfig {
    data object Disabled : ShippingAddressConfig

    data class Enabled(
        val allowedCountryCodes: List<String>? = null,
        val phoneNumberRequired: Boolean = false,
    ) : ShippingAddressConfig
}
