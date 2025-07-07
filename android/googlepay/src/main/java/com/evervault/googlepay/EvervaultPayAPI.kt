package com.evervault.googlepay

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.evervault.payments.R
import com.google.android.gms.wallet.PaymentData
import okhttp3.OkHttpClient
import okhttp3.Request
import okio.IOException
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Response
import okhttp3.ResponseBody
import org.json.JSONObject

interface EvervaultPayAPICallback {
    fun onFailure(e: java.io.IOException)
    fun onResponse(response: ResponseBody)
}

class EvervaultPayAPI(private val baseUrl: String, private val appUuid: String) {
    private val client = OkHttpClient()
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * @param merchantId String the Evervault merchant ID
     */
    fun getMerchantName(merchantId: String, callback: EvervaultPayAPICallback) {
        val request = Request.Builder()
            .url("${baseUrl}/frontend/merchants/${merchantId}")
            .get()
            .addHeader("x-evervault-app-id", this.appUuid)
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                mainHandler.post { callback.onFailure(IOException("Error")) }
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    if (!response.isSuccessful) {
                        callback.onFailure(IOException("Unexpected code $response"))
                        return
                    }
                    response.body?.let { body ->
                        callback.onResponse(body)
                    }
                }
            }
        })
    }

    /**
     * @param paymentData PaymentData object received from Google Pay on Android
     * @param environment WalletConstants.ENVIRONMENT_TEST or WalletConstants.ENVIRONMENT_PRODUCTION
     * @param callback Callback to handle the response from the Evervault server
     */
    fun fetchCryptogram(paymentData: PaymentData, merchantId: String, callback: EvervaultPayAPICallback) {
        // https://developers.google.com/pay/api/android/guides/resources/payment-data-cryptography#payment-method-token-structure

        val paymentInformation = paymentData.toJson()
        // Token will be null if PaymentDataRequest was not constructed using fromJson(String).
        val paymentMethodData = JSONObject(paymentInformation).getJSONObject("paymentMethodData")

        // This is the same as the web version.
        val tokenizationData = paymentMethodData.getJSONObject("tokenizationData")
        val token = JSONObject(tokenizationData.getString("token"))
        val googlePayCredentialsRequest = JSONObject()
            .put("merchantId", merchantId)
            .put("token", token)
        val body = googlePayCredentialsRequest.toString()
            .toRequestBody("application/json".toMediaTypeOrNull())
        val request = Request.Builder()
            .url("${baseUrl}/frontend/google-pay/credentials")
            .post(body)
            .addHeader("x-evervault-app-id", this.appUuid)
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

                    response.body?.let { body ->
                        callback.onResponse(body)
                    }
                }
            }
        })
    }
}
