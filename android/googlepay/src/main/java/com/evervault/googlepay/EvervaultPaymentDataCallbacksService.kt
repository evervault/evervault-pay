package com.evervault.googlepay

import com.google.android.gms.wallet.PaymentData
import com.google.android.gms.wallet.callback.BasePaymentDataCallbacks
import com.google.android.gms.wallet.callback.BasePaymentDataCallbacksService
import com.google.android.gms.wallet.callback.IntermediatePaymentData
import com.google.android.gms.wallet.callback.OnCompleteListener
import com.google.android.gms.wallet.callback.PaymentAuthorizationResult
import com.google.android.gms.wallet.callback.PaymentDataRequestUpdate

/**
 * Internal Google Pay service for payment authorization and shipping callbacks.
 *
 * The SDK decrypts the payment / resolves the shipping selection and invokes
 * the configured merchant handler.
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

            override fun onPaymentDataChanged(
                intermediatePaymentData: IntermediatePaymentData?,
                onCompleteListener: OnCompleteListener<PaymentDataRequestUpdate>,
            ) {
                if (intermediatePaymentData == null) {
                    onCompleteListener.complete(
                        shippingError("Payment data is unavailable", GooglePayShippingIntent.ShippingAddress),
                    )
                    return
                }

                GooglePayShippingCoordinator.recompute(
                    applicationContext,
                    intermediatePaymentData,
                    onCompleteListener,
                )
            }
        }
}
