package com.evervault.evpay

data class BillingAddress(
    val name: String?,
    val postalCode: String?,
    val countryCode: String?,
    val phoneNumber: String?,
    val address1: String?,
    val address2: String?,
    val address3: String?,
    val locality: String?,
    val administrativeArea: String?,
    val sortingCode: String?,
)
