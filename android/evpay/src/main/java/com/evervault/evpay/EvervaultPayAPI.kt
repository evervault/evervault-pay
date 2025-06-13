package com.evervault.evpay

import okhttp3.OkHttpClient
import okhttp3.Request
import okio.IOException
import com.google.gson.Gson
import com.google.gson.JsonSyntaxException
import okhttp3.Call
import okhttp3.Callback
import okhttp3.Response

class EvervaultPayAPI {
    private val client = OkHttpClient()

    fun fetchCryptogram() {
        val request = Request.Builder()
            .url("https://meowfacts.herokuapp.com")
            .build()

        client.newCall(request).enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                e.printStackTrace()
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    if (!response.isSuccessful) throw IOException("Unexpected code $response")

                    response.body?.string()?.let { jsonString ->
                        try {
                            val dpanResponse = Gson().fromJson(jsonString, DpanResponse::class.java)
                        } catch (_: JsonSyntaxException) {

                        }

                        try {
                            val fpanResponse = Gson().fromJson(jsonString, FpanResponse::class.java)
                        } catch (_: JsonSyntaxException) {

                        }
                    }
                }
            }
        })
    }
}
