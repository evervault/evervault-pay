package com.evervault.googlepay

import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.callback.BasePaymentDataCallbacks
import com.google.android.gms.wallet.callback.BasePaymentDataCallbacksService
import com.google.android.gms.wallet.callback.OnCompleteListener
import com.google.android.gms.wallet.callback.PaymentAuthorizationResult

/**
 * Internal Google Pay service for payment authorization callbacks.
 *
 * The SDK decrypts the payment and invokes the configured merchant handler.
 */
class EvervaultPaymentDataCallbacksService : BasePaymentDataCallbacksService() {
    override fun createPaymentDataCallbacks(): BasePaymentDataCallbacks =
        object : BasePaymentDataCallbacks() {
            override fun onPaymentAuthorized(
                paymentData: PaymentData?,
                onCompleteListener: OnCompleteListener<PaymentAuthorizationResult>,
            ) {
                if (paymentData == null) {
                    onCompleteListener.complete(
                        authorizationError("Payment data is unavailable"),
                    )
                    return
                }

                GooglePayAuthorizationCoordinator.authorize(
                    applicationContext,
                    paymentData,
                    onCompleteListener,
                )
            }
        }
}
