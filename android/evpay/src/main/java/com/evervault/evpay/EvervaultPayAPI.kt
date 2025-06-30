package com.evervault.evpay

import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.WalletConstants
import okhttp3.OkHttpClient
import okhttp3.Request
import okio.IOException
import com.google.gson.Gson
import com.google.gson.JsonSyntaxException
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import org.json.JSONObject

interface EvervaultPayAPICallback {
    fun onFailure(e: java.io.IOException)

    fun onResponse(response: DpanResponse)
}

class EvervaultPayAPI {
    private val client = OkHttpClient()

    /**
     * @param paymentData PaymentData object received from Google Pay on Android
     * @param environment WalletConstants.ENVIRONMENT_TEST or WalletConstants.ENVIRONMENT_PRODUCTION
     * @param callback Callback to handle the response from the Evervault server
     */
    fun fetchCryptogram(paymentData: PaymentData, merchant_id: String, environment: Int, callback: EvervaultPayAPICallback) {
        // https://developers.google.com/pay/api/android/guides/resources/payment-data-cryptography#payment-method-token-structure

        val paymentInformation = paymentData.toJson()
        // Token will be null if PaymentDataRequest was not constructed using fromJson(String).
        val paymentMethodData = JSONObject(paymentInformation).getJSONObject("paymentMethodData")

<<<<<<< Updated upstream
        val evervault_route = when (environment) {
            WalletConstants.ENVIRONMENT_PRODUCTION -> "https://api.evervault.com"
            WalletConstants.ENVIRONMENT_TEST -> "https://evervault.io"
=======
        val evervaultRoute = when (environment) {
            WalletConstants.ENVIRONMENT_PRODUCTION -> Constants.API_BASE_URL_PRODUCTION
            WalletConstants.ENVIRONMENT_TEST -> Constants.API_BASE_URL_TEST
>>>>>>> Stashed changes
            else -> return callback.onFailure(IOException("Invalid environment"))
        }

        // This is the same as the web version.
        val google_pay_credentials_request = JSONObject()
            .put("merchant_id", merchant_id)
            .put("token", paymentMethodData.getJSONObject("tokenizationData"))

        val body = google_pay_credentials_request.toString()
            .toRequestBody("application/json".toMediaTypeOrNull())
        val request = Request.Builder()
            .url("${evervault_route}/frontend/google-pay/credentials")
            .post(body)
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                callback.onFailure(e)
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    if (!response.isSuccessful) {
                        callback.onFailure(IOException("Unexpected code $response"))
                        return
                    }

                    response.body?.string()?.let { jsonString ->
                        try {
                            val dpanResponse = Gson().fromJson(jsonString, DpanResponse::class.java)
                            callback.onResponse(dpanResponse)
                        } catch (_: JsonSyntaxException) {
                            callback.onFailure(IOException("Invalid JSON response"))
                        }
                    }
                }
            }
        })
    }
}
