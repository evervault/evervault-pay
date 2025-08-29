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
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

abstract class PaymentState internal constructor() {
    object NotStarted : PaymentState()
    object Available : PaymentState()
    object Unavailable: PaymentState()
    class PaymentCompleted(val response: TokenResponse) : PaymentState()
    class Error(val code: Int, val message: String? = null) : PaymentState()
}


/**
 * Gateway Integration: Identify your gateway and your app's gateway merchant identifier.
 *
 *
 * The Google Pay API response will return an encrypted payment method capable of being charged
 * by a supported gateway after payer authorization.
 *
 * @return Payment data tokenization for the CARD payment method.
 * @throws JSONException
 * See [PaymentMethodTokenizationSpecification](https://developers.google.com/pay/api/android/reference/object.PaymentMethodTokenizationSpecification)
 */
private fun gatewayTokenizationSpecification(model: EvervaultPayViewModel) = JSONObject()
        .put("type", "PAYMENT_GATEWAY")
        .put("parameters", JSONObject(model.PAYMENT_GATEWAY_TOKENIZATION_PARAMETERS))

/**
 * Card networks supported by your app and your gateway.
 *
 * @return Allowed card networks
 * See [CardParameters](https://developers.google.com/pay/api/android/reference/object.CardParameters)
 */
private fun allowedCardNetworks(config: Config) = JSONArray(config.supportedNetworks.map { it.name })

/**
 * Describe your app's support for the CARD payment method.
 *
 *
 * The provided properties are applicable to both an IsReadyToPayRequest and a
 * PaymentDataRequest.
 *
 * @return A CARD PaymentMethod object describing accepted cards.
 * @throws JSONException
 * See [PaymentMethod](https://developers.google.com/pay/api/android/reference/object.PaymentMethod)
 */
// Optionally, you can add billing address/phone number associated with a CARD payment method.
private fun baseCardPaymentMethod(model: EvervaultPayViewModel): JSONObject =
    JSONObject()
        .put("type", "CARD")
        .put("parameters", JSONObject()
            .put("allowedAuthMethods", JSONArray(model.config.supportedMethods.asGooglePayStrings()))
            .put("allowedCardNetworks", allowedCardNetworks(model.config))
            .put("billingAddressRequired", true)
            .put("billingAddressParameters", JSONObject()
                .put("format", "FULL")
            )
        )

/**
 * Describe the expected returned payment data for the CARD payment method
 *
 * @return A CARD PaymentMethod describing accepted cards and optional fields.
 * @throws JSONException
 * See [PaymentMethod](https://developers.google.com/pay/api/android/reference/object.PaymentMethod)
 */
private fun cardPaymentMethod(model: EvervaultPayViewModel) = baseCardPaymentMethod(model)
    .put("tokenizationSpecification", gatewayTokenizationSpecification(model))

internal fun allowedPaymentMethods(model: EvervaultPayViewModel) = JSONArray().put(cardPaymentMethod(model))

/**
 * Create a Google Pay API base request object with properties used in all requests.
 *
 * @return Google Pay API base request object.
 * @throws JSONException
 */
internal val baseRequest = JSONObject()
    .put("apiVersion", 2)
    .put("apiVersionMinor", 0)

/**
 * An object describing accepted forms of payment by your app, used to determine a viewer's
 * readiness to pay.
 *
 * @return API version and payment methods supported by the app.
 * See [IsReadyToPayRequest](https://developers.google.com/pay/api/android/reference/object.IsReadyToPayRequest)
 */
fun isReadyToPayRequest(model: EvervaultPayViewModel): JSONObject? =
    try {
        baseRequest
            .put("allowedPaymentMethods", JSONArray().put(baseCardPaymentMethod(model)))
    } catch (e: JSONException) {
        null
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
        allowedPaymentMethods = allowedPaymentMethods(model).toString(),
        theme = theme,
        type = type,
        enabled = isClickable
    )
}
