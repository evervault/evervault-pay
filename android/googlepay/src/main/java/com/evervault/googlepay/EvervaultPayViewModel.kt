package com.evervault.googlepay

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.ResolvableApiException
import com.google.android.gms.wallet.IsReadyToPayRequest
import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.PaymentDataRequest
import com.google.android.gms.wallet.PaymentsClient
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
import org.json.JSONArray
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

    var isClickable = MutableStateFlow(true)
    private var isStarted = false
    private fun started() = this.isStarted

    internal val paymentsClient: PaymentsClient by lazy {
        createPaymentsClient(application, config.environment)
    }

    private val apiClient = EvervaultPayAPI(when (config.environment) {
        EvervaultConstants.ENVIRONMENT_TEST -> Constants.API_BASE_URL_TEST
        EvervaultConstants.ENVIRONMENT_PRODUCTION -> Constants.API_BASE_URL_PRODUCTION
        else -> Constants.API_BASE_URL_PRODUCTION
    }, config.appId)

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
    suspend fun createPaymentRequest(transaction: Transaction): PaymentDataRequest {
        val merchantName = getMerchantName()

        val paymentDataRequestJson = baseRequest
            .put("allowedPaymentMethods", allowedPaymentMethods(this))
            .put(
                "transactionInfo", JSONObject()
                    .put("displayItems", JSONArray(transaction.lineItems.map {
                        JSONObject()
                            .put("label", it.label)
                            .put("type", "LINE_ITEM")
                            .put("price", it.amount.amount)
                            .put("status", "FINAL")
                    }))
                    .put("totalPriceLabel", "Total")
                    .put("totalPrice", transaction.total.amount)
                    .put("totalPriceStatus", "FINAL")
                    .put("countryCode", transaction.country)
                    .put("currencyCode", transaction.currency)
            )
            .put("merchantInfo", JSONObject().put("merchantName", merchantName))

        return PaymentDataRequest.fromJson(paymentDataRequestJson.toString())
    }

    /**
     * Returns a PaymentResult without invoking AutoResolveHelper.
     */
    suspend fun getPaymentData(transaction: Transaction): PaymentResult {
        return try {
            val request = createPaymentRequest(transaction)
            val task = paymentsClient.loadPaymentData(request)

            try {
                val paymentData = task.await()
                PaymentResult.Success(paymentData)
            } catch (e: ResolvableApiException) {
                PaymentResult.Resolvable(e.resolution)
            } catch (e: Exception) {
                PaymentResult.Failure(e)
            }
        } catch (e: Exception) {
            PaymentResult.Failure(e)
        }
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

                    val payState = extractPaymentBillingName(paymentData)?.let {
                        tokenResponse.billingAddress = it
                        PaymentState.PaymentCompleted(response = tokenResponse)
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
        return paymentsClient.isReadyToPay(request).await()
    }

    private fun extractPaymentBillingName(paymentData: PaymentData): BillingAddress? {
        val paymentInformation = paymentData.toJson()
        return try {
            val paymentMethodData = JSONObject(paymentInformation).getJSONObject("paymentMethodData")
            val billingAddress = paymentMethodData
                .getJSONObject("info")
                .getJSONObject("billingAddress")
            Gson().fromJson(billingAddress.toString(), BillingAddress::class.java)
        } catch (error: JSONException) {
            Log.e(LOG_TAG, "Error: $error")
            null
        }
    }
}
