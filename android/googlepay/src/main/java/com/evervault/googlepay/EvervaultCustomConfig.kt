package com.evervault.googlepay

// This is a singleton for the app to override behaviour if desired.
object EvervaultCustomConfig {
    // Always set this to production
    // To override this in a test app,
    // assign a new value to "EvervaultCustomConfig.apiBaseUrl"
    // before calling the `EvervaultPayViewModel`
    var apiBaseUrl: String = Constants.API_BASE_URL_PRODUCTION
}
