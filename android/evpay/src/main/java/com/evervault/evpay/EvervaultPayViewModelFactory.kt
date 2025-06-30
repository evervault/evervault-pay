package com.evervault.evpay

import android.app.Application
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider

class EvervaultPayViewModelFactory(
    private val application: Application,
    private val appId: String,
    private val merchantId: String,
) : ViewModelProvider.Factory {
    override fun <T : ViewModel> create(modelClass: Class<T>): T {
        if (modelClass.isAssignableFrom(EvervaultPayViewModel::class.java)) {
            @Suppress("UNCHECKED_CAST")
            return EvervaultPayViewModel(application, appId, merchantId) as T
        }
        throw IllegalArgumentException("Unknown ViewModel class")
    }
}