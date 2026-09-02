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

/**
 * Google's assessment of the card and the buyer, when `assuranceDetailsRequired`
 * is set on the request.
 *
 * https://developers.google.com/pay/api/android/reference/response-objects#AssuranceDetails
 */
data class AssuranceDetails(
    val accountVerified: Boolean = false,
    val cardHolderAuthenticated: Boolean = false,
)

data class Merchant(
    val id: String,
    val name: String,
)

sealed interface TokenResponse {
    var billingAddress: BillingAddress?
    val email: String?
    var shippingAddress: ShippingAddress?
    var shippingOption: ShippingOption?
}

data class GooglePayCard(
    val brand: String? = null,
    val funding: String? = null,
    val segment: String? = null,
    val country: String? = null,
    val currency: String? = null,
    val issuer: String? = null,
    val paymentMethodType: String? = null,
    val lastFour: String? = null,
    val displayName: String? = null,
    val assuranceDetails: AssuranceDetails? = null,
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

    /** Retains the constructor signature from releases before `lastFour`/`displayName`. */
    constructor(
        brand: String?,
        funding: String?,
        segment: String?,
        country: String?,
        currency: String?,
        issuer: String?,
        paymentMethodType: String?,
    ) : this(
        brand = brand,
        funding = funding,
        segment = segment,
        country = country,
        currency = currency,
        issuer = issuer,
        paymentMethodType = paymentMethodType,
        lastFour = null,
        displayName = null,
        assuranceDetails = null,
    )

    /** Retains the constructor signature from releases before `assuranceDetails`. */
    constructor(
        brand: String?,
        funding: String?,
        segment: String?,
        country: String?,
        currency: String?,
        issuer: String?,
        paymentMethodType: String?,
        lastFour: String?,
        displayName: String?,
    ) : this(
        brand = brand,
        funding = funding,
        segment = segment,
        country = country,
        currency = currency,
        issuer = issuer,
        paymentMethodType = paymentMethodType,
        lastFour = lastFour,
        displayName = displayName,
        assuranceDetails = null,
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
    override var shippingAddress: ShippingAddress? = null,
    override var shippingOption: ShippingOption? = null,
) : TokenResponse {
    /** Retains the constructor signature from releases before `shippingAddress`/`shippingOption`. */
    constructor(
        card: GooglePayCard,
        token: PaymentToken,
        cryptogram: String,
        eci: String,
        billingAddress: BillingAddress?,
        messageId: String?,
        messageExpiration: String?,
        email: String?,
    ) : this(
        card = card,
        token = token,
        cryptogram = cryptogram,
        eci = eci,
        billingAddress = billingAddress,
        messageId = messageId,
        messageExpiration = messageExpiration,
        email = email,
        shippingAddress = null,
        shippingOption = null,
    )
}

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
    val lastFour: String? = null,
    val displayName: String? = null,
    val assuranceDetails: AssuranceDetails? = null,
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

    /** Retains the constructor signature from releases before `lastFour`/`displayName`. */
    constructor(
        number: String,
        expiry: CardExpiry,
        brand: String?,
        funding: String?,
        segment: String?,
        country: String?,
        currency: String?,
        issuer: String?,
        paymentMethodType: String?,
    ) : this(
        number = number,
        expiry = expiry,
        brand = brand,
        funding = funding,
        segment = segment,
        country = country,
        currency = currency,
        issuer = issuer,
        paymentMethodType = paymentMethodType,
        lastFour = null,
        displayName = null,
        assuranceDetails = null,
    )

    /** Retains the constructor signature from releases before `assuranceDetails`. */
    constructor(
        number: String,
        expiry: CardExpiry,
        brand: String?,
        funding: String?,
        segment: String?,
        country: String?,
        currency: String?,
        issuer: String?,
        paymentMethodType: String?,
        lastFour: String?,
        displayName: String?,
    ) : this(
        number = number,
        expiry = expiry,
        brand = brand,
        funding = funding,
        segment = segment,
        country = country,
        currency = currency,
        issuer = issuer,
        paymentMethodType = paymentMethodType,
        lastFour = lastFour,
        displayName = displayName,
        assuranceDetails = null,
    )
}

data class CardResponse(
    val card: FpanCardDetails,
    override var billingAddress: BillingAddress? = null,
    val messageId: String? = null,
    val messageExpiration: String? = null,
    override val email: String? = null,
    override var shippingAddress: ShippingAddress? = null,
    override var shippingOption: ShippingOption? = null,
) : TokenResponse {
    /** Retains the constructor signature from releases before `shippingAddress`/`shippingOption`. */
    constructor(
        card: FpanCardDetails,
        billingAddress: BillingAddress?,
        messageId: String?,
        messageExpiration: String?,
        email: String?,
    ) : this(
        card = card,
        billingAddress = billingAddress,
        messageId = messageId,
        messageExpiration = messageExpiration,
        email = email,
        shippingAddress = null,
        shippingOption = null,
    )
}
