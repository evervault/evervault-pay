package com.evervault.googlepay

internal object Constants {
    const val API_BASE_URL_PRODUCTION = "https://api.evervault.com"
    const val API_BASE_URL_TEST = "https://api.evervault.io"
    const val GATEWAY_TOKENIZATION_NAME = "evervault"
    val SUPPORTED_NETWORKS = CardNetwork.entries
    val SUPPORTED_METHODS = listOf(CardAuthMethod.PAN_ONLY, CardAuthMethod.CRYPTOGRAM_3DS)
}