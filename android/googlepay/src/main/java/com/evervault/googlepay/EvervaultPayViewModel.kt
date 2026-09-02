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
import com.google.gson.JsonDeserializationContext
import com.google.gson.JsonDeserializer
import com.google.gson.JsonElement
import com.google.gson.JsonParseException
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
import kotlin.coroutines.resumeWithException
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

        GooglePayAuthorizationConfigStore.save(getApplication(), config)
        GooglePayShippingConfigStore.save(getApplication(), config)

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
                    cont.resumeWithException(e)
                }

                override fun onResponse(response: ResponseBody) {
                    try {
                        val merchant = Gson().fromJson(response.string(), Merchant::class.java)
                        cont.resume(merchant.name)
                    } catch (e: Exception) {
                        cont.resumeWithException(e)
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

        if (config.googlePayShipping != null) {
            GooglePayShippingStateStore.start(transaction, merchantName)
        }

        return PaymentDataRequest.fromJson(
            buildPaymentRequestJson(config, transaction, merchantName),
        )
    }

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
        GooglePayShippingStateStore.clear()
        val state = classifyPaymentFailure(error)
        if (state is PaymentState.Error) {
            Log.e(LOG_TAG, "Payment failed", error)
        }
        _paymentState.update { state }
    }

    fun handlePaymentData(paymentData: PaymentData) {
        if (config.googlePayAuthorization != null) {
            _paymentState.update { PaymentState.PaymentAuthorized }
            return
        }

        viewModelScope.launch {
            try {
                _paymentState.update {
                    PaymentState.PaymentCompleted(
                        response = decryptPaymentData(apiClient, paymentData, config.merchantId),
                    )
                }
            } catch (error: Exception) {
                Log.e(LOG_TAG, "An exception occurred while fetching the cryptogram", error)
                _paymentState.update {
                    PaymentState.Error(CommonStatusCodes.INTERNAL_ERROR, "Error decoding payment token data")
                }
            } finally {
                // No-authorization payments never retry once the sheet has closed, so
                // this is always the true end of the attempt, success or failure.
                GooglePayShippingStateStore.clear()
            }
        }
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

internal suspend fun decryptPaymentData(
    apiClient: EvervaultPayAPI,
    paymentData: PaymentData,
    merchantId: String,
): TokenResponse {
    val tokenResponse = apiClient.fetchCryptogram(paymentData, merchantId)
    val paymentInformation = paymentData.toJson()
    extractPaymentBillingName(paymentInformation)?.let { billingName ->
        tokenResponse.billingAddress = billingName
    }
    extractPaymentShippingAddress(paymentInformation)?.let { shippingAddress ->
        tokenResponse.shippingAddress = shippingAddress
    }
    extractPaymentShippingOption()?.let { shippingOption ->
        tokenResponse.shippingOption = shippingOption
    }

    val responseWithPaymentMethodType = attachPaymentMethodType(
        attachPaymentEmail(tokenResponse, paymentInformation),
        paymentInformation,
    )
    val responseWithDisplayDetails =
        attachPaymentCardDisplayDetails(responseWithPaymentMethodType, paymentInformation)
    return attachAssuranceDetails(responseWithDisplayDetails, paymentInformation)
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

// Unlike billingAddress (nested under paymentMethodData.info), Google Pay
// returns shippingAddress as a top-level field on the final PaymentData.
internal fun extractPaymentShippingAddress(paymentInformation: String): ShippingAddress? =
    try {
        val shippingAddress = JSONObject(paymentInformation).optJSONObject("shippingAddress")
        shippingAddress?.let { Gson().fromJson(it.toString(), ShippingAddress::class.java) }
    } catch (error: JSONException) {
        Log.e(EvervaultPayViewModel.LOG_TAG, "Error: $error")
        null
    }

// Google Pay's final PaymentData never includes the selected shipping option id,
// only the redacted mid-flow callback does, so the SDK has to remember it via
// GooglePayShippingStateStore for it to still be available here.
internal fun extractPaymentShippingOption(): ShippingOption? {
    val state = GooglePayShippingStateStore.current() ?: return null
    return state.transaction.shippingOptions.find { it.id == state.selectedShippingOptionId }
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

internal fun attachPaymentCardDisplayDetails(
    tokenResponse: TokenResponse,
    paymentInformation: String,
): TokenResponse {
    val displayName = extractPaymentDisplayName(paymentInformation)
    val lastFour = extractPaymentLastFour(paymentInformation)
    if (displayName == null && lastFour == null) return tokenResponse

    return when (tokenResponse) {
        is NetworkTokenResponse -> tokenResponse.copy(
            card = tokenResponse.card.copy(displayName = displayName, lastFour = lastFour),
        )
        is CardResponse -> tokenResponse.copy(
            card = tokenResponse.card.copy(displayName = displayName, lastFour = lastFour),
        )
    }
}

internal fun extractPaymentDisplayName(paymentInformation: String): String? =
    try {
        JSONObject(paymentInformation)
            .getJSONObject("paymentMethodData")
            .optString("description")
            .takeIf { it.isNotBlank() }
    } catch (error: JSONException) {
        Log.e(EvervaultPayViewModel.LOG_TAG, "Error: $error")
        null
    }

internal fun extractPaymentLastFour(paymentInformation: String): String? =
    try {
        val paymentMethodData = JSONObject(paymentInformation).getJSONObject("paymentMethodData")
        val fourDigitRegex = Regex("(\\d{4})$")

        val cardDetails = paymentMethodData.optJSONObject("info")?.optString("cardDetails")
        val lastFour = cardDetails?.let { fourDigitRegex.find(it)?.value }

        if (lastFour != null) {
            lastFour
        } else {
            // If the last four digits are not found in cardDetails, try to get them from the description
            fourDigitRegex.find(paymentMethodData.optString("description"))?.value
        }
    } catch (error: JSONException) {
        Log.e(EvervaultPayViewModel.LOG_TAG, "Error: $error")
        null
    }

internal fun attachAssuranceDetails(
    tokenResponse: TokenResponse,
    paymentInformation: String,
): TokenResponse {
    val assuranceDetails = extractAssuranceDetails(paymentInformation) ?: return tokenResponse

    return when (tokenResponse) {
        is NetworkTokenResponse -> tokenResponse.copy(
            card = tokenResponse.card.copy(assuranceDetails = assuranceDetails),
        )
        is CardResponse -> tokenResponse.copy(
            card = tokenResponse.card.copy(assuranceDetails = assuranceDetails),
        )
    }
}

internal fun extractAssuranceDetails(paymentInformation: String): AssuranceDetails? =
    try {
        JSONObject(paymentInformation)
            .getJSONObject("paymentMethodData")
            .getJSONObject("info")
            .optJSONObject("assuranceDetails")
            ?.let {
                AssuranceDetails(
                    accountVerified = it.optBoolean("accountVerified"),
                    cardHolderAuthenticated = it.optBoolean("cardHolderAuthenticated"),
                )
            }
    } catch (error: JSONException) {
        Log.e(EvervaultPayViewModel.LOG_TAG, "Error: $error")
        null
    }
