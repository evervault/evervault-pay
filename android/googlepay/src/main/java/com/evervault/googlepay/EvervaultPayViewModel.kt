package com.evervault.googlepay

import android.app.Application
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.ResolvableApiException
import com.google.android.gms.wallet.IsReadyToPayRequest
import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.PaymentDataRequest
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.google.gson.JsonDeserializationContext
import com.google.gson.JsonDeserializer
import com.google.gson.JsonElement
import com.google.gson.JsonParseException
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
import java.lang.reflect.Type

// Handle decoding between FPAN and DPAN repsonse types
class TokenResponseAdapter : JsonDeserializer<TokenResponse> {
    override fun deserialize(
        json: JsonElement,
        typeOfT: Type,
        ctx: JsonDeserializationContext
    ): TokenResponse {

        val obj = json.asJsonObject
        if (obj.has("cryptogram")) {
            return ctx.deserialize<NetworkTokenResponse>(obj, NetworkTokenResponse::class.java)
        } else if (obj.has("card")) {
            return ctx.deserialize<CardResponse>(obj, CardResponse::class.java)
        } else {
            throw JsonParseException("Could not deserialize response")
        }
    }
}

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
    val PAYMENT_GATEWAY_TOKENIZATION_PARAMETERS = gatewayTokenizationParameters(config)

    companion object {
        const val LOAD_PAYMENT_DATA_REQUEST_CODE = 991
        val LOG_TAG = "EvervaultPayViewModel"
    }

    private val _paymentState: MutableStateFlow<PaymentState> = MutableStateFlow(PaymentState.NotStarted)
    val paymentState: StateFlow<PaymentState> = _paymentState.asStateFlow()

    var isClickable = MutableStateFlow(true)
    private var isStarted = false
    private fun started() = this.isStarted

    internal val sdkConfig by lazy {
        CoroutineScope(Dispatchers.IO).async {
            apiClient.fetchSDKConfig(config.appId)
        }
    }

    internal val paymentsClient by lazy {
        CoroutineScope(Dispatchers.IO).async {
            // Create the local google pay client based on if it's an Evervault sandbox app or not.
            createPaymentsClient(
                application, if (sdkConfig.await().is_sandbox) {
                    EvervaultConstants.ENVIRONMENT_TEST
                } else {
                    EvervaultConstants.ENVIRONMENT_PRODUCTION
                }
            )
        }
    }

    private val apiClient = EvervaultPayAPI(EvervaultCustomConfig.apiBaseUrl, config.appId)

    fun start() {
        if (this.isStarted) return
        this.isStarted = true

        viewModelScope.launch {
            verifyGooglePayReadiness()
        }
    }

    suspend fun isAvailable(): Boolean {
        return try {
            fetchCanUseGooglePay()
        } catch (e: Exception) {
            false
        }
    }

    suspend fun getMerchantName(): String = suspendCancellableCoroutine { cont ->
        this.apiClient.getMerchantName(
            config.merchantId,
            object : EvervaultPayAPICallback {
                override fun onFailure(e: IOException) {
                    Log.e(LOG_TAG, "An exception occurred while fetching the merchant", e)
                    _paymentState.update { PaymentState.Error(CommonStatusCodes.INTERNAL_ERROR, e.message) }
                    cont.cancel()
                }

                override fun onResponse(response: ResponseBody) {
                    try {
                        val merchant = Gson().fromJson(response.string(), Merchant::class.java)
                        cont.resume(merchant.name)
                    } catch (e: Exception) {
                        _paymentState.update { PaymentState.Error(CommonStatusCodes.INTERNAL_ERROR, e.message) }
                        cont.cancel()
                    }
                }
            }
        )
    }

    /**
     * Build the Google Pay PaymentDataRequest for the given transaction.
     */
    suspend fun createPaymentRequest(transaction: Transaction): PaymentDataRequest =
        PaymentDataRequest.fromJson(
            buildPaymentRequestJson(config, transaction, getMerchantName())
        )

    /**
     * Fetches the `PaymentResult` after doing the token exchange from Evervault.
     */
    suspend fun getPaymentData(transaction: Transaction): PaymentResult {
        return try {
            val request = createPaymentRequest(transaction)
            val task = paymentsClient.await().loadPaymentData(request)

            try {
                val paymentData = task.await()
                PaymentResult.Success(paymentData)
            } catch (e: ResolvableApiException) {
                PaymentResult.Resolvable(e.resolution)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PaymentResult.Failure(e)
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            PaymentResult.Failure(e)
        }
    }

    fun handlePaymentFailure(error: Throwable) {
        val state = classifyPaymentFailure(error)
        if (state is PaymentState.Error) {
            Log.e(LOG_TAG, "Payment failed", error)
        }
        _paymentState.update { state }
    }

    fun handlePaymentData(paymentData: PaymentData) {
        this.apiClient.fetchCryptogram(paymentData, config.merchantId, object : EvervaultPayAPICallback {
            override fun onFailure(e: IOException) {
                Log.e(LOG_TAG, "An exception occured while fetching the cryptogram", e)
                _paymentState.update { PaymentState.Error(CommonStatusCodes.INTERNAL_ERROR, e.toString()) }
            }

            override fun onResponse(response: ResponseBody) {
                try {
                    val raw = response.string()
                    val gson: Gson = GsonBuilder()
                        .registerTypeAdapter(TokenResponse::class.java, TokenResponseAdapter())
                        .create()
                    val tokenResponse = gson.fromJson(raw, TokenResponse::class.java)

                    val paymentInformation = paymentData.toJson()
                    extractPaymentBillingName(paymentInformation)?.let { billingName ->
                        tokenResponse.billingAddress = billingName
                    }
                    val responseWithEmail = attachPaymentEmail(tokenResponse, paymentInformation)
                    val responseWithPaymentMethodType = attachPaymentMethodType(
                        responseWithEmail,
                        paymentInformation,
                    )

                    _paymentState.update {
                        PaymentState.PaymentCompleted(response = responseWithPaymentMethodType)
                    }
                } catch (_: JsonSyntaxException) {
                    _paymentState.update {
                        PaymentState.Error(CommonStatusCodes.INTERNAL_ERROR,"Error decoding payment token data")
                    }
                }
            }
        })
    }

    private suspend fun verifyGooglePayReadiness() {
        if (!this.started()) {
            return _paymentState.update { PaymentState.Error(CommonStatusCodes.DEVELOPER_ERROR, "Must call 'start' first") }
        }

        val newUiState: PaymentState = try {
            if (fetchCanUseGooglePay()) PaymentState.Available else PaymentState.Unavailable
        } catch (exception: ApiException) {
            PaymentState.Error(exception.statusCode, exception.message)
        }

        _paymentState.update { newUiState }
    }

    private suspend fun fetchCanUseGooglePay(): Boolean {
        val request = IsReadyToPayRequest.fromJson(isReadyToPayRequest(this).toString())
        return paymentsClient.await().isReadyToPay(request).await()
    }
}

internal fun extractPaymentBillingName(paymentInformation: String): BillingAddress? =
    try {
        val paymentMethodData = JSONObject(paymentInformation).getJSONObject("paymentMethodData")
        val billingAddress = paymentMethodData
            .getJSONObject("info")
            .getJSONObject("billingAddress")
        Gson().fromJson(billingAddress.toString(), BillingAddress::class.java)
    } catch (error: JSONException) {
        Log.e(EvervaultPayViewModel.LOG_TAG, "Error: $error")
        null
    }

internal fun attachPaymentEmail(
    tokenResponse: TokenResponse,
    paymentInformation: String,
): TokenResponse {
    val email = extractPaymentEmail(paymentInformation) ?: return tokenResponse

    return when (tokenResponse) {
        is NetworkTokenResponse -> tokenResponse.copy(email = email)
        is CardResponse -> tokenResponse.copy(email = email)
    }
}

internal fun extractPaymentEmail(paymentInformation: String): String? =
    try {
        JSONObject(paymentInformation).optString("email").takeIf { it.isNotBlank() }
    } catch (error: JSONException) {
        Log.e(EvervaultPayViewModel.LOG_TAG, "Error: $error")
        null
    }

internal fun attachPaymentMethodType(
    tokenResponse: TokenResponse,
    paymentInformation: String,
): TokenResponse {
    val paymentMethodType = extractPaymentMethodType(paymentInformation) ?: return tokenResponse

    return when (tokenResponse) {
        is NetworkTokenResponse -> tokenResponse.copy(
            card = tokenResponse.card.copy(paymentMethodType = paymentMethodType),
        )
        is CardResponse -> tokenResponse.copy(
            card = tokenResponse.card.copy(paymentMethodType = paymentMethodType),
        )
    }
}

internal fun extractPaymentMethodType(paymentInformation: String): String? =
    try {
        when (
            JSONObject(paymentInformation)
                .getJSONObject("paymentMethodData")
                .getJSONObject("info")
                .optString("cardFundingSource")
        ) {
            "CREDIT" -> "credit"
            "DEBIT" -> "debit"
            "PREPAID" -> "prepaid"
            else -> null
        }
    } catch (error: JSONException) {
        Log.e(EvervaultPayViewModel.LOG_TAG, "Error: $error")
        null
    }
