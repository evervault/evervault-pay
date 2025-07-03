package com.evervault.googlepay

import com.google.pay.button.ButtonTheme
import com.google.pay.button.ButtonType

data class Config(
    val appId: String,
    val merchantId: String,
    val environment: Int = EvervaultConstants.ENVIRONMENT_TEST,
    val supportedNetworks: List<CardNetwork>  = Constants.SUPPORTED_NETWORKS,
    val supportedMethods: List<String> = Constants.SUPPORTED_METHODS,
)