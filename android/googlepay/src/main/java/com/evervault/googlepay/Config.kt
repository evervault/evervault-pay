package com.evervault.googlepay

data class Config(
    val appId: String,
    val merchantId: String,
    val supportedNetworks: List<CardNetwork>  = Constants.SUPPORTED_NETWORKS,
    val supportedMethods: List<CardAuthMethod> = Constants.SUPPORTED_METHODS,
    val billingAddress: BillingAddressConfig = BillingAddressConfig.Enabled(),
    val emailRequired: Boolean = false,
    val googlePayAuthorization: GooglePayAuthorizationConfig? = null,
) {
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
