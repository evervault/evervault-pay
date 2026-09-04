package com.evervault.googlepay

/**
 * The shipping address the buyer entered in the Google Pay sheet.
 *
 * A dedicated type rather than a reuse of [BillingAddress]: Google Pay never
 * returns a phone number on the shipping address, even when one is requested
 * on billing, so sharing a type would carry an always-null field here.
 */
data class ShippingAddress(
    val name: String?,
    val postalCode: String?,
    val countryCode: String?,
    val address1: String?,
    val address2: String?,
    val address3: String?,
    val locality: String?,
    val administrativeArea: String?,
    val sortingCode: String?,
)
