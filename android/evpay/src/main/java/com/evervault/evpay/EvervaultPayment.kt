package com.evervault.evpay

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.google.pay.button.PayButton
import androidx.compose.ui.platform.testTag
import androidx.compose.foundation.layout.fillMaxWidth
import com.google.android.gms.tasks.OnCompleteListener
import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.PaymentDataRequest
import com.google.android.gms.wallet.Wallet
import com.google.android.gms.wallet.WalletConstants
import org.json.JSONObject
import kotlin.enums.enumEntries

inline fun <reified T : Enum<T>> printAllValues() {
    println(enumEntries<T>().joinToString { it.name })
}

@Composable
fun EvervaultPayment(paymentRequest: Transaction, context: Context, onResult: OnCompleteListener<PaymentData>) {
    val allowedPaymentMethods = listOf("CRYPTOGRAM_3DS")

    // TODO: Restrict card networks
    // TODO: Add our merchant ID
    // TODO: Add line items.
    val onClickHandler: () -> Unit = {
        val paymentDataRequestJson = JSONObject()
            .put("apiVersion", 2)
            .put("apiVersionMinor", 0)
            .put("allowedPaymentMethods", allowedPaymentMethods)
            .put("transactionInfo", JSONObject()
                .put("totalPrice", paymentRequest.lineItems.last().amount.amount)
                .put("totalPriceStatus", "FINAL")
                .put("countryCode", paymentRequest.country)
                .put("currencyCode", paymentRequest.currency))
            .put("merchantInfo", JSONObject().put("merchantName", "Example Merchant"))
        val request = PaymentDataRequest.fromJson(paymentDataRequestJson.toString())

        val walletOptions = Wallet.WalletOptions.Builder()
            .setEnvironment(WalletConstants.ENVIRONMENT_TEST)
            .build()

        val paymentsClient = Wallet.getPaymentsClient(context, walletOptions)
        val task = paymentsClient.loadPaymentData(request)
        task.addOnCompleteListener(onResult)
    }

    // TODO: Pass in modifier
    // TODO: Pass in button customizations
    PayButton(modifier = Modifier.testTag("payButton").fillMaxWidth(), onClick = onClickHandler, allowedPaymentMethods = allowedPaymentMethods.toString())
}
