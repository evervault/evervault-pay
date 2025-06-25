package com.evervault.evpay

// https://github.com/evervault/oxide/blob/700a4d667047cd249f81434fde5e02ef8a23981c/crates/customer-api/src/routers/frontend/google_wallet.rs#L55
data class CardExpiry(
    val month: Int,
    val year: Int
)

data class PaymentToken(
    val number: String,
    val expiry: CardExpiry,
    val token_service_provider: String
)

data class GooglePayCard(
    val brand: String?,
    val funding: String?,
    val segment: String?,
    val country: String?,
    val currency: String?,
    val issuer: String?
)

data class DpanResponse(
    val card: GooglePayCard,
    val token: PaymentToken,
    val cryptogram: String,
    val eci: String
)
