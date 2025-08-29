package com.evervault.googlepay

data class Config(
    val appId: String,
    val merchantId: String,
    val supportedNetworks: List<CardNetwork>  = Constants.SUPPORTED_NETWORKS,
    val supportedMethods: List<CardAuthMethod> = Constants.SUPPORTED_METHODS,
)
