package com.evervault.evpay

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.wallet.IsReadyToPayRequest
import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.PaymentsClient
import com.google.android.gms.wallet.WalletConstants
import com.google.android.gms.wallet.contract.ApiTaskResult
import com.google.gson.Gson
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException

/**
 * Changing this to ENVIRONMENT_PRODUCTION will make the API return chargeable card information.
 * Please refer to the documentation to read about the required steps needed to enable
 * ENVIRONMENT_PRODUCTION.
 *
 * @value #PAYMENTS_ENVIRONMENT
 */
class EvervaultPayViewModel(application: Application, private val appId: String, private val merchantId: String) : AndroidViewModel(application) {
    // use WalletConstants.ENVIRONMENT_PRODUCTION or WalletConstants.ENVIRONMENT_TEST
    var environment: Int = WalletConstants.ENVIRONMENT_TEST

    val MERCHANT_NAME = "Evervault"

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
        "gatewayMerchantId" to merchantId
    )

    /**
     * The allowed networks to be requested from the API. If the user has cards from networks not
     * specified here in their account, these will not be offered for them to choose in the popup.
     *
     * This is defaulted to all known card brands.
     */
    var SUPPORTED_NETWORKS = CardNetwork.entries.map { it.name }

    /**
     * The Google Pay API may return cards on file on Google.com (PAN_ONLY) and/or a device token on
     * an Android device authenticated with a 3-D Secure cryptogram (CRYPTOGRAM_3DS).
     *
     * We only support CRYPTOGRAM_3DS at this time.
     */
    val SUPPORTED_METHODS = listOf("CRYPTOGRAM_3DS")

    companion object {
        val LOG_TAG = "EvervaultPayViewModel"
    }

    private val _paymentUiState: MutableStateFlow<PaymentUiState> = MutableStateFlow(PaymentUiState.NotStarted)
    val paymentUiState: StateFlow<PaymentUiState> = _paymentUiState.asStateFlow()

    // A client for interacting with the Google Pay API.
    internal val paymentsClient: PaymentsClient by lazy { createPaymentsClient(application, this.environment) }

    private var isStarted = false
    fun started() = this.isStarted

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

    private val apiClient = EvervaultPayAPI(this.appId)

    fun handlePaymentData(taskResult: ApiTaskResult<PaymentData>) {
        when (taskResult.status.statusCode) {
            CommonStatusCodes.SUCCESS -> {
                taskResult.result!!.let {
                    this.setPaymentData(it)
                }
            }
            CommonStatusCodes.CANCELED -> {
                Log.w(LOG_TAG, "Payment task canceled")
            }
            else -> {
                this.handleError(taskResult.status.statusCode, "Unknown error occured")
            }
        }
    }

    /**
     * Determine the user's ability to pay with a payment method supported by your app and display
     * a Google Pay payment button.
    ) */
    private suspend fun verifyGooglePayReadiness() {
        if (!this.started()) {
            return _paymentUiState.update { PaymentUiState.Error(CommonStatusCodes.DEVELOPER_ERROR, "Must call 'start' before calling this method") }
        }

        val newUiState: PaymentUiState = try {
            if (fetchCanUseGooglePay()) {
                PaymentUiState.Available
            } else {
                PaymentUiState.Error(CommonStatusCodes.ERROR)
            }
        } catch (exception: ApiException) {
            PaymentUiState.Error(exception.statusCode, exception.message)
        }

        _paymentUiState.update { newUiState }
    }

    /**
     * Determine the user's ability to pay with a payment method supported by your app.
     * You must call 'start' before calling this method.
    ) */
    suspend fun fetchCanUseGooglePay(): Boolean {
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

    internal fun setPaymentData(paymentData: PaymentData) {
        this.apiClient.fetchCryptogram(paymentData, merchantId, this.environment, object : EvervaultPayAPICallback {
            override fun onFailure(e: IOException) {
                Log.e(LOG_TAG, "An exception occured while fetching the cryptogram", e)
                _paymentUiState.update { PaymentUiState.Error(CommonStatusCodes.INTERNAL_ERROR) }
            }

            override fun onResponse(response: DpanResponse) {
                val payState = extractPaymentBillingName(paymentData)?.let {
                    response.billingAddress = it
                    PaymentUiState.PaymentCompleted(response = response)
                } ?: PaymentUiState.Error(CommonStatusCodes.INTERNAL_ERROR)
                _paymentUiState.update { payState }
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
