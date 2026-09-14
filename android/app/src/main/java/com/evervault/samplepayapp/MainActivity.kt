package com.evervault.samplepayapp

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.evervault.googlepay.Amount
import com.evervault.googlepay.CardNetwork
import com.evervault.googlepay.Config
import com.evervault.googlepay.CardResponse
import com.evervault.googlepay.EvervaultButtonTheme
import com.evervault.googlepay.EvervaultButtonType
import com.evervault.googlepay.EvervaultConstants
import com.evervault.googlepay.EvervaultCustomConfig
import com.evervault.googlepay.EvervaultPayViewModel
import com.evervault.googlepay.EvervaultPayViewModelFactory
import com.evervault.googlepay.GooglePayAuthorizationConfig
import com.evervault.googlepay.GooglePayAuthorizationErrorReason
import com.evervault.googlepay.GooglePayAuthorizationHandler
import com.evervault.googlepay.GooglePayAuthorizationResult
import com.evervault.googlepay.GooglePayShippingConfig
import com.evervault.googlepay.GooglePayShippingErrorReason
import com.evervault.googlepay.GooglePayShippingHandler
import com.evervault.googlepay.GooglePayShippingIntent
import com.evervault.googlepay.GooglePayShippingUpdateRequest
import com.evervault.googlepay.GooglePayShippingUpdateResult
import com.evervault.googlepay.NetworkTokenResponse
import com.evervault.googlepay.LineItem
import com.evervault.googlepay.PaymentState
import com.evervault.googlepay.ShippingAddress
import com.evervault.googlepay.ShippingAddressConfig
import com.evervault.googlepay.ShippingOption
import com.evervault.googlepay.Transaction
import com.evervault.googlepay.TokenResponse

/** All non-null parts of a [ShippingAddress], for display - the SDK doesn't format one for you. */
private fun formatAddress(address: ShippingAddress): String =
    listOfNotNull(
        address.name,
        address.address1,
        address.address2,
        address.address3,
        address.locality,
        address.administrativeArea,
        address.postalCode,
        address.sortingCode,
        address.countryCode,
    ).joinToString(", ")

/**
 * Demo-only: stashes the redacted mid-flow address so the result screen can
 * show it next to the final [TokenResponse.shippingAddress] for comparison.
 * A production handler has no reason to keep this around.
 */
private object SampleShippingAddressCapture {
    @Volatile
    var lastIntermediateAddress: ShippingAddress? = null
}

/** Demonstrates the callback contract. Production handlers must authorize with a merchant backend. */
class SampleGooglePayAuthorizationHandler : GooglePayAuthorizationHandler {
    override suspend fun authorize(payment: TokenResponse): GooglePayAuthorizationResult =
        when (BuildConfig.GOOGLE_PAY_AUTHORIZATION_RESULT) {
            "reject" -> GooglePayAuthorizationResult.Reject(
                message = "Sample authorization rejected this payment.",
                reason = GooglePayAuthorizationErrorReason.PaymentDataInvalid,
            )
            else -> GooglePayAuthorizationResult.Accept
        }
}

/**
 * Demonstrates the callback contract: rejects unserviceable destinations,
 * charges a flat rate for some, and otherwise recomputes the total for the
 * selected shipping option.
 */
class SampleGooglePayShippingHandler : GooglePayShippingHandler {
    override suspend fun recompute(request: GooglePayShippingUpdateRequest): GooglePayShippingUpdateResult {
        SampleShippingAddressCapture.lastIntermediateAddress = request.shippingAddress

        val countryCode = request.shippingAddress?.countryCode

        if (countryCode in UNSERVICEABLE_COUNTRIES) {
            return GooglePayShippingUpdateResult.Reject(
                message = "We don't ship to this destination yet.",
                intent = GooglePayShippingIntent.ShippingAddress,
                reason = GooglePayShippingErrorReason.ShippingAddressUnserviceable,
            )
        }

        val standardOnly = countryCode in STANDARD_ONLY_COUNTRIES
        if (standardOnly && request.selectedShippingOption.id != "standard") {
            return GooglePayShippingUpdateResult.Reject(
                message = "Only Standard shipping is available for this destination.",
                intent = GooglePayShippingIntent.ShippingOption,
                reason = GooglePayShippingErrorReason.ShippingOptionInvalid,
            )
        }

        val currency = request.transaction.currency
        val baseTotal = request.transaction.total.format(currency).toDouble()
        val shippingCost = if (standardOnly) {
            STANDARD_ONLY_SHIPPING_COST
        } else {
            request.selectedShippingOption.amount.format(currency).toDouble()
        }

        return GooglePayShippingUpdateResult.Accept(
            lineItems = request.transaction.lineItems.toList() +
                LineItem(request.selectedShippingOption.label, Amount("%.2f".format(shippingCost))),
            total = Amount("%.2f".format(baseTotal + shippingCost)),
        )
    }

    private companion object {
        val UNSERVICEABLE_COUNTRIES = setOf("BR", "CA")
        val STANDARD_ONLY_COUNTRIES = setOf("HK", "JP")
        const val STANDARD_ONLY_SHIPPING_COST = 14.95
    }
}

class MainActivity : AppCompatActivity() {

    private val model: EvervaultPayViewModel by viewModels {
        // Optional: Override the API Base URL when needed
        // here by setting `EvervaultCustomConfig.apiBaseUrl`
        EvervaultPayViewModelFactory(
            application,
            Config(
                appId = BuildConfig.EVERVAULT_APP_ID,
                merchantId = BuildConfig.EVERVAULT_MERCHANT_ID,
                supportedNetworks = listOf(
                    CardNetwork.VISA,
                    CardNetwork.MASTERCARD
                ),
                emailRequired = true,
                googlePayAuthorization = if (BuildConfig.ENABLE_GOOGLE_PAY_AUTHORIZATION) {
                    GooglePayAuthorizationConfig(SampleGooglePayAuthorizationHandler::class.java)
                } else {
                    null
                },
                shippingAddress = if (BuildConfig.ENABLE_GOOGLE_PAY_SHIPPING) {
                    ShippingAddressConfig.Enabled()
                } else {
                    ShippingAddressConfig.Disabled
                },
                googlePayShipping = if (BuildConfig.ENABLE_GOOGLE_PAY_SHIPPING) {
                    GooglePayShippingConfig(SampleGooglePayShippingHandler::class.java)
                } else {
                    null
                },
            )
        )
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val transaction = Transaction(
            country = "GB",
            currency = "GBP",
            total = Amount("54.99"),
            lineItems = arrayOf(
                LineItem("Men's Tech Shell Full Zip", Amount("50.00")),
                LineItem("Something small", Amount("04.99")),
            ),
            shippingOptions = if (BuildConfig.ENABLE_GOOGLE_PAY_SHIPPING) {
                listOf(
                    // No price: rate varies by destination, see SampleGooglePayShippingHandler.
                    ShippingOption("standard", "Standard Shipping", Amount("0.00")),
                    // Price baked in: rate never varies, so it's safe to show up front.
                    ShippingOption("express", "Express Shipping: £9.99", Amount("9.99")),
                )
            } else {
                emptyList()
            },
            defaultShippingOptionId = if (BuildConfig.ENABLE_GOOGLE_PAY_SHIPPING) "standard" else null,
        )

        setContent {
            LaunchedEffect(Unit) {
                model.start()
            }

            val payState: PaymentState by model.paymentState.collectAsState()

            when (val state = payState) {
                is PaymentState.Unavailable -> Text("Google Pay is not available.")
                is PaymentState.Available, is PaymentState.Cancelled -> ProductScreen(
                    model = model,
                    transaction = transaction,
                    type = EvervaultButtonType.Order,
                    theme = EvervaultButtonTheme.Light,
                )
                is PaymentState.PaymentAuthorized -> Text("Payment authorized")
                is PaymentState.PaymentCompleted -> {
                    val token = state.response
                    val shippingDetails =
                        "Shipping Address (mid-flow, redacted): ${
                            SampleShippingAddressCapture.lastIntermediateAddress?.let(::formatAddress)
                                ?: "Not returned"
                        }\n" +
                            "Shipping Address (final): ${
                                token.shippingAddress?.let(::formatAddress) ?: "Not returned"
                            }\n" +
                            "Shipping Option: ${token.shippingOption?.label ?: "Not returned"}"

                    when (token) {
                        is NetworkTokenResponse -> {
                            Text(
                                "Encrypted Network Token Cryptogram: ${token.cryptogram}\n" +
                                    "Email: ${token.email ?: "Not returned"}\n" +
                                    shippingDetails
                            )
                        }
                        is CardResponse -> {
                            Text(
                                "Encrypted Card Number: ${token.card.number}\n" +
                                    "Email: ${token.email ?: "Not returned"}\n" +
                                    shippingDetails
                            )
                        }
                    }
                }

                is PaymentState.Error -> Text("Error: ${state.message}")
                is PaymentState.NotStarted -> CircularProgressIndicator()
            }
        }
    }
}