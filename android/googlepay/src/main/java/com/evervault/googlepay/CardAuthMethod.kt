package com.evervault.googlepay

enum class CardAuthMethod(val gpValue: String) {
    PAN_ONLY("PAN_ONLY"),
    CRYPTOGRAM_3DS("CRYPTOGRAM_3DS");
}

fun List<CardAuthMethod>.asGooglePayStrings(): List<String> =
    map(CardAuthMethod::gpValue)