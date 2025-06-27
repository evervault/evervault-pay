package com.evervault.samplepayapp

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.evervault.evpay.Amount
import com.evervault.evpay.EvervaultPayViewModel
import com.evervault.evpay.EvervaultPayViewModelFactory
import com.evervault.evpay.LineItem
import com.evervault.evpay.PaymentUiState
import com.evervault.evpay.Transaction
import com.google.android.gms.wallet.WalletConstants
import com.google.android.gms.wallet.contract.TaskResultContracts.GetPaymentDataResult

class MainActivity : AppCompatActivity() {
    private val paymentDataLauncher = registerForActivityResult(GetPaymentDataResult()) { taskResult ->
        this.model.handlePaymentData(taskResult)
    }

    private val model: EvervaultPayViewModel by viewModels {
        EvervaultPayViewModelFactory(application, "app_c7c594325ed9", "merchant_3ca5d6aec6ca")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Set values and call start
        this.model.environment = WalletConstants.ENVIRONMENT_TEST
        this.model.start()

        val transaction = Transaction("GB", "GBP", arrayOf(
            LineItem("Men's Tech Shell Full Zip", Amount("50.20"))
        ))

        setContent {
            val payState: PaymentUiState by this.model.paymentUiState.collectAsStateWithLifecycle()

            ProductScreen(
                title = "Men's Tech Shell Full-Zip",
                description = "A versatile full-zip that you can wear all day long and even...",
                price = "$50.20",
                image = R.drawable.ts_10_11019a,
                payUiState = payState,
                transaction = transaction,
                model = this.model,
                displayPaymentModalLauncher = this.paymentDataLauncher
            )
        }
    }
}