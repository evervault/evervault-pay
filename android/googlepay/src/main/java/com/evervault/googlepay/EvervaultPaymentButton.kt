package com.evervault.googlepay

import android.app.Activity
import android.content.Context
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.google.pay.button.PayButton
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status
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
    /** The merchant accepted an inline-authorized payment. */
    object PaymentAuthorized : PaymentState()
    class PaymentCompleted(val response: TokenResponse) : PaymentState()
    object Cancelled : PaymentState()
    class Error(val code: Int, val message: String? = null) : PaymentState()
}

/**
 * Maps a Google Pay failure onto the state the buyer's action deserves. A dismissed
 * sheet reports [PaymentState.Cancelled]; everything else is a genuine
 * [PaymentState.Error].
 */
internal fun classifyPaymentFailure(statusCode: Int?, message: String?): PaymentState =
    if (statusCode == CommonStatusCodes.CANCELED) {
        PaymentState.Cancelled
    } else {
        PaymentState.Error(statusCode ?: CommonStatusCodes.INTERNAL_ERROR, message)
    }

internal fun classifyPaymentFailure(error: Throwable): PaymentState =
    if (error is ApiException) {
        classifyPaymentFailure(error.statusCode, error.status.statusMessage ?: error.message)
    } else {
        classifyPaymentFailure(null, error.message)
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

object EvervaultPaymentButtonDefaults {
    /** Google's own default when `buttonRadius` is unset. The web SDK uses the same value. */
    val Radius: Dp = 12.dp
}

@Composable
fun EvervaultPaymentButton(
    modifier: Modifier,
    paymentRequest: Transaction,
    model: EvervaultPayViewModel,
    theme: EvervaultButtonTheme = EvervaultButtonTheme.Dark,
    type: EvervaultButtonType = EvervaultButtonType.Pay,
    radius: Dp = EvervaultPaymentButtonDefaults.Radius,
) {
    val activity = LocalContext.current as Activity
    val scope = rememberCoroutineScope()

    val isClickable by model.isClickable.collectAsState(initial = false)

    val launcher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartIntentSenderForResult()
    ) { result ->
        when (result.resultCode) {
            Activity.RESULT_OK -> {
                val data = result.data?.let(PaymentData::getFromIntent)
                if (data != null) {
                    model.handlePaymentData(data)
                } else {
                    model.handlePaymentFailure(IllegalStateException("No payment data"))
                }
            }
            Activity.RESULT_CANCELED -> model.handlePaymentFailure(
                ApiException(Status(CommonStatusCodes.CANCELED)),
            )
            AutoResolveHelper.RESULT_ERROR -> {
                val status = result.data?.let(AutoResolveHelper::getStatusFromIntent)
                model.handlePaymentFailure(
                    status?.let(::ApiException)
                        ?: IllegalStateException("Google Pay resolution failed"),
                )
            }
            else -> model.handlePaymentFailure(
                IllegalStateException("Unknown Google Pay result: ${result.resultCode}"),
            )
        }
        model.isClickable.update { true }
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
                    model.handlePaymentFailure(result.throwable)
                    model.isClickable.update { true }
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
        radius = radius,
        enabled = isClickable
    )
}
