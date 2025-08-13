package com.evervault.googlepay

import android.app.PendingIntent
import com.google.android.gms.wallet.PaymentData

sealed interface PaymentResult {
    data class Success(val paymentData: PaymentData) : PaymentResult
    data class Resolvable(val intentSender: PendingIntent) : PaymentResult
    data class Failure(val throwable: Throwable) : PaymentResult
}
