package com.evervault.googlepay;

import com.google.android.gms.wallet.PaymentData;
import com.google.android.gms.wallet.callback.BasePaymentDataCallbacks;
import com.google.android.gms.wallet.callback.BasePaymentDataCallbacksService;
import com.google.android.gms.wallet.callback.OnCompleteListener;
import com.google.android.gms.wallet.callback.PaymentAuthorizationResult;

/**
 * Internal Google Pay service for payment authorization callbacks.
 *
 * This service is inactive until a later SDK release provides a merchant
 * authorization handler. It completes unexpected callbacks with an error.
 */
public final class EvervaultPaymentDataCallbacksService extends BasePaymentDataCallbacksService {
    @Override
    protected BasePaymentDataCallbacks createPaymentDataCallbacks() {
        return new BasePaymentDataCallbacks() {
            @Override
            protected void onPaymentAuthorized(
                PaymentData paymentData,
                OnCompleteListener<PaymentAuthorizationResult> onCompleteListener
            ) {
                onCompleteListener.complete(
                    PaymentAuthorizationResult.fromJson(
                        "{\"transactionState\":\"ERROR\",\"error\":{"
                            + "\"reason\":\"OTHER_ERROR\","
                            + "\"intent\":\"PAYMENT_AUTHORIZATION\","
                            + "\"message\":\"Payment authorization is unavailable\"}}"
                    )
                );
            }
        };
    }
}
