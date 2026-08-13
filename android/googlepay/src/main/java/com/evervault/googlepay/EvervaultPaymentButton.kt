package com.evervault.googlepay

import android.app.Activity
import android.content.Context
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.google.pay.button.PayButton
import com.google.android.gms.tasks.Task
import com.google.android.gms.wallet.AutoResolveHelper
import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.PaymentDataRequest
import com.google.android.gms.wallet.PaymentsClient
import com.google.android.gms.wallet.Wallet
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

abstract class PaymentState internal constructor() {
    object NotStarted : PaymentState()
    object Available : PaymentState()
    object Unavailable: PaymentState()
    class PaymentCompleted(val response: TokenResponse) : PaymentState()
    class Error(val code: Int, val message: String? = null) : PaymentState()
}


/**
 * Creates an instance of [PaymentsClient] for use in an [Context] using the
 * environment and theme set in [Constants].
 *
 * @param context from the caller activity.
 */
fun createPaymentsClient(context: Context, environment: Int): PaymentsClient {
    val walletOptions = Wallet.WalletOptions.Builder()
        .setEnvironment(environment)
        .build()

    return Wallet.getPaymentsClient(context, walletOptions)
}

typealias EvervaultButtonTheme = com.google.pay.button.ButtonTheme
typealias EvervaultButtonType = com.google.pay.button.ButtonType

@Composable
fun EvervaultPaymentButton(
    modifier: Modifier,
    paymentRequest: Transaction,
    model: EvervaultPayViewModel,
    theme: EvervaultButtonTheme = EvervaultButtonTheme.Dark,
    type: EvervaultButtonType = EvervaultButtonType.Pay,
) {
    val activity = LocalContext.current as Activity
    val scope = rememberCoroutineScope()

    val isClickable by model.isClickable.collectAsState(initial = false)

    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartIntentSenderForResult()
    ) { result ->
        if (result.resultCode == Activity.RESULT_OK) {
            val data = PaymentData.getFromIntent(result.data!!)
            if (data != null) {
                model.handlePaymentData(data)
            }
        }
    }

    val onClickHandler = onClick@{
        if (!model.isClickable.value) return@onClick
        model.isClickable.update { false }

        scope.launch {
            when (val result = model.getPaymentData(paymentRequest)) {
                is PaymentResult.Success -> {
                    model.handlePaymentData(result.paymentData)
                    model.isClickable.update { true }
                }
                is PaymentResult.Resolvable -> {
                    val request = IntentSenderRequest.Builder(result.intentSender).build()
                    launcher.launch(request)
                }
                is PaymentResult.Failure -> {
                    model.isClickable.update { true }
                    Log.e(EvervaultPayViewModel.LOG_TAG, "Payment failed", result.throwable)
                }
            }
        }
    }

    PayButton(
        modifier = modifier,
        onClick = onClickHandler,
        allowedPaymentMethods = allowedPaymentMethods(model.config).toString(),
        theme = theme,
        type = type,
        enabled = isClickable
    )
}
