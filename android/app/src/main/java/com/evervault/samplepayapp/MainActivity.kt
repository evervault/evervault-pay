package com.evervault.samplepayapp

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import android.util.Log
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.wallet.contract.TaskResultContracts.GetPaymentDataResult

class MainActivity : AppCompatActivity() {
//    override fun onCreate(savedInstanceState: Bundle?) {
//        super.onCreate(savedInstanceState)
//        enableEdgeToEdge()
//        setContentView(R.layout.activity_main)
//        ViewCompat.setOnApplyWindowInsetsListener(findViewById(R.id.main)) { v, insets ->
//            val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
//            v.setPadding(systemBars.left, systemBars.top, systemBars.right, systemBars.bottom)
//            insets
//        }
//    }

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

        setContent {
            val payState: PaymentUiState by model.paymentUiState.collectAsStateWithLifecycle()
            ProductScreen(
                title = "Men's Tech Shell Full-Zip",
                description = "A versatile full-zip that you can wear all day long and even...",
                price = "$50.20",
                image = R.drawable.ts_10_11019a,
                payUiState = payState,
                onGooglePayButtonClick = this::requestPayment,
            )
        }
    }

    private fun requestPayment() {
        val task = model.getLoadPaymentDataTask(priceLabel = "50.2")
        task.addOnCompleteListener(paymentDataLauncher::launch)
    }
}