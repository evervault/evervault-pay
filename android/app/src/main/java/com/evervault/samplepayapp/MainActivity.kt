package com.evervault.samplepayapp

import android.content.Intent
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
import com.evervault.googlepay.EvervaultPayViewModel
import com.evervault.googlepay.EvervaultPayViewModelFactory
import com.evervault.googlepay.NetworkTokenResponse
import com.evervault.googlepay.LineItem
import com.evervault.googlepay.PaymentState
import com.evervault.googlepay.Transaction

class MainActivity : AppCompatActivity() {

    private val model: EvervaultPayViewModel by viewModels {
        EvervaultPayViewModelFactory(
            application,
            Config(
                appId = "app_1234567890",
                merchantId = "merchant_1234567890",
                supportedNetworks = listOf(
                    CardNetwork.VISA,
                    CardNetwork.MASTERCARD
                ),
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
            )
        )
        setContent {
            LaunchedEffect(Unit) {
                model.start()
            }

            val payState: PaymentState by model.paymentState.collectAsState()

            when (val state = payState) {
                is PaymentState.Unavailable -> Text("Google Pay is not available.")
                is PaymentState.Available -> ProductScreen(
                    model = model,
                    transaction = transaction,
                    type = EvervaultButtonType.Order,
                    theme = EvervaultButtonTheme.Light,
                )
                is PaymentState.PaymentCompleted -> {
                    when (val token = state.response) {
                        is NetworkTokenResponse -> {
                            Text("Encrypted Network Token Cryptogram: ${token.cryptogram}")
                        }
                        is CardResponse -> {
                            Text("Encrypted Card Number: ${token.card.number}")
                        }
                    }
                }
                is PaymentState.Error -> Text("Error: ${state.message}")
                is PaymentState.NotStarted -> CircularProgressIndicator()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        model.handlePaymentDataIntent(requestCode, resultCode, data)
    }
}