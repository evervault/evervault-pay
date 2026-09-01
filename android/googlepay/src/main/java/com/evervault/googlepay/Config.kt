package com.evervault.googlepay

data class Config(
    val appId: String,
    val merchantId: String,
    val supportedNetworks: List<CardNetwork>  = Constants.SUPPORTED_NETWORKS,
    val supportedMethods: List<CardAuthMethod> = Constants.SUPPORTED_METHODS,
    val billingAddress: BillingAddressConfig = BillingAddressConfig.Enabled(),
    val emailRequired: Boolean = false,
    val googlePayAuthorization: GooglePayAuthorizationConfig? = null,
    val assuranceDetailsRequired: Boolean = false,
    val allowPrepaidCards: Boolean = true,
    val allowCreditCards: Boolean = true,
    /**
     * Shows the button only to buyers with an existing supported payment method.
     * This excludes buyers who could add a card during checkout.
     */
    val existingPaymentMethodRequired: Boolean = false,
) {
    /** Retains the constructor signature from releases before this config batch. */
    constructor(
        appId: String,
        merchantId: String,
        supportedNetworks: List<CardNetwork>,
        supportedMethods: List<CardAuthMethod>,
        billingAddress: BillingAddressConfig,
        emailRequired: Boolean,
        googlePayAuthorization: GooglePayAuthorizationConfig?,
    ) : this(
        appId = appId,
        merchantId = merchantId,
        supportedNetworks = supportedNetworks,
        supportedMethods = supportedMethods,
        billingAddress = billingAddress,
        emailRequired = emailRequired,
        googlePayAuthorization = googlePayAuthorization,
        assuranceDetailsRequired = false,
        allowPrepaidCards = true,
        allowCreditCards = true,
        existingPaymentMethodRequired = false,
    )

    /** Retains the constructor signature from releases before `emailRequired`. */
    constructor(
        appId: String,
        merchantId: String,
        supportedNetworks: List<CardNetwork>,
        supportedMethods: List<CardAuthMethod>,
        billingAddress: BillingAddressConfig,
    ) : this(
        appId = appId,
        merchantId = merchantId,
        supportedNetworks = supportedNetworks,
        supportedMethods = supportedMethods,
        billingAddress = billingAddress,
        emailRequired = false,
        googlePayAuthorization = null,
    )
}
