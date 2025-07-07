package com.evervault.googlepay

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.evervault.payments.R
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.wallet.AutoResolveHelper
import com.google.android.gms.wallet.IsReadyToPayRequest
import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.PaymentsClient
import com.google.gson.Gson
import com.google.gson.JsonSyntaxException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.tasks.await
import okhttp3.ResponseBody
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException
import kotlin.coroutines.resume

internal fun Context.evervaultBaseUrl(): String =
    getString(R.string.evervault_base_url)


/**
 * Changing this to ENVIRONMENT_PRODUCTION will make the API return chargeable card information.
 * Please refer to the documentation to read about the required steps needed to enable
 * ENVIRONMENT_PRODUCTION.
 *
 * @value #PAYMENTS_ENVIRONMENT
 */
class EvervaultPayViewModel(application: Application, val config: Config) : AndroidViewModel(application) {
    /**
     * The name of the payment processor/gateway.
     **/
    val PAYMENT_GATEWAY_TOKENIZATION_NAME = Constants.GATEWAY_TOKENIZATION_NAME

    /**
     * Custom parameters required by the processor/gateway.
     * In many cases, your processor / gateway will only require a gatewayMerchantId.
     * Please refer to your processor's documentation for more information. The number of parameters
     * required and their names vary depending on the processor.
     */
    val PAYMENT_GATEWAY_TOKENIZATION_PARAMETERS = mapOf(
        "gateway" to PAYMENT_GATEWAY_TOKENIZATION_NAME,
        "gatewayMerchantId" to config.merchantId
    )

    companion object {
        const val LOAD_PAYMENT_DATA_REQUEST_CODE = 991
        val LOG_TAG = "EvervaultPayViewModel"
    }

    private val _paymentState: MutableStateFlow<PaymentState> = MutableStateFlow(PaymentState.NotStarted)
    val paymentState: StateFlow<PaymentState> = _paymentState.asStateFlow()

    // A client for interacting with the Google Pay API.
    internal val paymentsClient: PaymentsClient by lazy { createPaymentsClient(application, config.environment) }

    private var isStarted = false
    private fun started() = this.isStarted

    fun start() {
        if (this.isStarted) {
            // Only supports starting once.
            return
        }

        this.isStarted = true

        viewModelScope.launch {
            verifyGooglePayReadiness()
        }
    }

    private val apiClient = EvervaultPayAPI(application.evervaultBaseUrl(), config.appId)

    suspend fun getMerchantName(): String = suspendCancellableCoroutine { cont ->
        this.apiClient.getMerchantName(
            config.merchantId,
            object : EvervaultPayAPICallback {
                override fun onFailure(e: IOException) {
                    Log.e(LOG_TAG, "An exception occurred while fetching the merchant", e)
                    _paymentState.update { PaymentState.Error(CommonStatusCodes.INTERNAL_ERROR, e.message)}
                    cont.cancel()
                }

                override fun onResponse(response: ResponseBody) {
                    try {
                        val merchant = Gson().fromJson(response.string(), Merchant::class.java)
                        cont.resume(merchant.name)
                    } catch (e: Exception) {
                        _paymentState.update { PaymentState.Error(CommonStatusCodes.INTERNAL_ERROR, e.message)}
                        cont.cancel()
                    }
                }
            }
        )
    }

    fun handlePaymentDataIntent(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != LOAD_PAYMENT_DATA_REQUEST_CODE) return
        when (resultCode) {
            Activity.RESULT_OK -> {
                val paymentData = PaymentData.getFromIntent(data!!)
                if (paymentData != null) {
                    setPaymentData(paymentData)
                    } else {
                        handleError(CommonStatusCodes.INTERNAL_ERROR, "No payment data")
                    }
                }
            Activity.RESULT_CANCELED -> {
                Log.w(LOG_TAG, "Payment cancelled by user")
                }
            AutoResolveHelper.RESULT_ERROR -> {
                val status = AutoResolveHelper.getStatusFromIntent(data!!)
                handleError(status?.statusCode ?: CommonStatusCodes.INTERNAL_ERROR,
                    status?.statusMessage)
                }
            }
        }

    /**
     * Determine the user's ability to pay with a payment method supported by your app and display
     * a Google Pay payment button.
    ) */
    private suspend fun verifyGooglePayReadiness() {
        if (!this.started()) {
            return _paymentState.update { PaymentState.Error(CommonStatusCodes.DEVELOPER_ERROR, "Must call 'start' before calling this method") }
        }

        val newUiState: PaymentState = try {
            if (fetchCanUseGooglePay()) {
                PaymentState.Available
            } else {
                PaymentState.Unavailable
            }
        } catch (exception: ApiException) {
            PaymentState.Error(exception.statusCode, exception.message)
        }

        _paymentState.update { newUiState }
    }

    /**
     * Determine the user's ability to pay with a payment method supported by your app.
     * You must call 'start' before calling this method.
    ) */
    private suspend fun fetchCanUseGooglePay(): Boolean {
        val request = IsReadyToPayRequest.fromJson(isReadyToPayRequest(this).toString())
        return this.paymentsClient.isReadyToPay(request).await()
    }

    /**
     * At this stage, the user has already seen a popup informing them an error occurred. Normally,
     * only logging is required.
     *
     * @param statusCode will hold the value of any constant from CommonStatusCode or one of the
     * WalletConstants.ERROR_CODE_* constants.
     * @see [
     * Wallet Constants Library](https://developers.google.com/android/reference/com/google/android/gms/wallet/WalletConstants)
     */
    private fun handleError(statusCode: Int, message: String?) {
        Log.e(LOG_TAG, "Error code: $statusCode, Message: $message")
    }

    private fun setPaymentData(paymentData: PaymentData) {
        this.apiClient.fetchCryptogram(paymentData, config.merchantId, object : EvervaultPayAPICallback {
            override fun onFailure(e: IOException) {
                Log.e(LOG_TAG, "An exception occured while fetching the cryptogram", e)
                _paymentState.update { PaymentState.Error(CommonStatusCodes.INTERNAL_ERROR, e.toString()) }
            }

            override fun onResponse(response: ResponseBody) {
                try {
                    val dpanResponse = Gson().fromJson(response.string(), DpanResponse::class.java)

                    val payState = extractPaymentBillingName(paymentData)?.let {
                        dpanResponse.billingAddress = it
                        PaymentState.PaymentCompleted(response = dpanResponse)
                    } ?: PaymentState.Error(CommonStatusCodes.INTERNAL_ERROR)
                    _paymentState.update { payState }
                } catch (_: JsonSyntaxException) {
                    _paymentState.update {
                        PaymentState.Error(CommonStatusCodes.INTERNAL_ERROR, "Error decoding payment token data")
                    }
                }
            }
        })
    }

    private fun extractPaymentBillingName(paymentData: PaymentData): BillingAddress? {
        val paymentInformation = paymentData.toJson()

        try {
            // Token will be null if PaymentDataRequest was not constructed using fromJson(String).
            val paymentMethodData = JSONObject(paymentInformation).getJSONObject("paymentMethodData")
            val billingAddress = paymentMethodData
                .getJSONObject("info")
                .getJSONObject("billingAddress")
            return Gson().fromJson(billingAddress.toString(), BillingAddress::class.java)
        } catch (error: JSONException) {
            Log.e(LOG_TAG, "Error: $error")
        }

        return null
    }
}
