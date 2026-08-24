package com.evervault.googlepay

// https://github.com/evervault/oxide/blob/700a4d667047cd249f81434fde5e02ef8a23981c/crates/customer-api/src/routers/frontend/google_wallet.rs#L55
data class CardExpiry(
    val month: Int,
    val year: Int
)

data class PaymentToken(
    val number: String,
    val expiry: CardExpiry,
    val tokenServiceProvider: String
)

data class Merchant(
    val id: String,
    val name: String,
)

sealed interface TokenResponse {
    var billingAddress: BillingAddress?
    val email: String?
}

data class GooglePayCard(
    val brand: String? = null,
    val funding: String? = null,
    val segment: String? = null,
    val country: String? = null,
    val currency: String? = null,
    val issuer: String? = null,
    val paymentMethodType: String? = null,
) {
    /** Retains the constructor signature from releases before `paymentMethodType`. */
    constructor(
        brand: String?,
        funding: String?,
        segment: String?,
        country: String?,
        currency: String?,
        issuer: String?,
    ) : this(
        brand = brand,
        funding = funding,
        segment = segment,
        country = country,
        currency = currency,
        issuer = issuer,
        paymentMethodType = null,
    )
}

data class NetworkTokenResponse(
    val card: GooglePayCard,
    val token: PaymentToken,
    val cryptogram: String,
    val eci: String,
    override var billingAddress: BillingAddress? = null,
    val messageId: String? = null,
    val messageExpiration: String? = null,
    override val email: String? = null,
) : TokenResponse

data class FpanCardDetails(
    val number: String,
    val expiry: CardExpiry,
    val brand: String? = null,
    val funding: String? = null,
    val segment: String? = null,
    val country: String? = null,
    val currency: String? = null,
    val issuer: String? = null,
    val paymentMethodType: String? = null,
) {
    /** Retains the constructor signature from releases before `paymentMethodType`. */
    constructor(
        number: String,
        expiry: CardExpiry,
        brand: String?,
        funding: String?,
        segment: String?,
        country: String?,
        currency: String?,
        issuer: String?,
    ) : this(
        number = number,
        expiry = expiry,
        brand = brand,
        funding = funding,
        segment = segment,
        country = country,
        currency = currency,
        issuer = issuer,
        paymentMethodType = null,
    )
}

data class CardResponse(
    val card: FpanCardDetails,
    override var billingAddress: BillingAddress? = null,
    val messageId: String? = null,
    val messageExpiration: String? = null,
    override val email: String? = null,
) : TokenResponse
