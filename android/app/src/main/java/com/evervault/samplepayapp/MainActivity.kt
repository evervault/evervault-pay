package com.evervault.samplepayapp

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import android.util.Log
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.evervault.evpay.Amount
import com.evervault.evpay.LineItem
import com.evervault.evpay.PaymentUiState
import com.evervault.evpay.Transaction
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.wallet.contract.TaskResultContracts.GetPaymentDataResult

class MainActivity : AppCompatActivity() {
    private val paymentDataLauncher = registerForActivityResult(GetPaymentDataResult()) { taskResult ->
        when (taskResult.status.statusCode) {
            CommonStatusCodes.SUCCESS -> {
                taskResult.result!!.let {
                    Log.i("Google Pay result:", it.toJson())
                    model.setPaymentData(it)
                }
            }
            //CommonStatusCodes.CANCELED -> The user canceled
            //CommonStatusCodes.DEVELOPER_ERROR -> The API returned an error (it.status: Status)
            //else -> Handle internal and other unexpected errors
        }
    }

    private val model: CheckoutViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val transaction = Transaction("GB", "GBP", arrayOf(
            LineItem("Men's Tech Shell Full Zip", Amount("50.20"))
        ))

        setContent {
            val payState: PaymentUiState by model.paymentUiState.collectAsStateWithLifecycle()

            ProductScreen(
                title = "Men's Tech Shell Full-Zip",
                description = "A versatile full-zip that you can wear all day long and even...",
                price = "$50.20",
                image = R.drawable.ts_10_11019a,
                payUiState = payState,
                transaction = transaction,
                paymentsClient = this.model.paymentsClient,
                onResult = this.paymentDataLauncher
            )
        }
    }
}