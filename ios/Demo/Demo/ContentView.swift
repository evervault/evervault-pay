//
//  ContentView.swift
//  Demo
//
//  Created by Jake Grogan on 12/06/2025.
//

import SwiftUI
import EvervaultPayment

fileprivate func buildTransaction() -> EvervaultPayment.Transaction {
    return try! .disbursement(.init(
        country: "IE",
        currency: "EUR",
        paymentSummaryItems: [
            SummaryItem(label: "Withdrawal Summary", amount: Amount("41.00")),
            SummaryItem(label: "Crypto Balance", amount: Amount("25.00")),
            SummaryItem(label: "EUR Balance", amount: Amount("15.00")),
        ],
        disbursementItem: SummaryItem(label: "Disbursement", amount: Amount("41.00")),
        instantOutFee: SummaryItem(label: "Instant funds out fee", amount: Amount("1.00")),
        requiredRecipientDetails: [
            .emailAddress,
            .phoneNumber,
        ],
        merchantCapability: MerchantCapability.instantFundsOut
    ))
}

struct ContentView: View {
    @State private var applePayResponse: ApplePayResponse? = nil
    let transaction = buildTransaction()
    
    var body: some View {
        VStack(spacing: 20) {
            if (EvervaultPaymentViewRepresentable.isAvailable()) {
                EvervaultPaymentViewRepresentable(
                    appId: "YOUR_EVERVAULT_APP_ID",
                    appleMerchantId: "YOUR_APPLE_MERCHANT_ID",
                    transaction: self.transaction,
                    supportedNetworks: [.visa, .masterCard, .amex],
                    buttonStyle: .whiteOutline,
                    buttonType: .checkout,
                    authorizedResponse: $applePayResponse) { result in
                        switch result {
                        case .success(_):
                            print("Payment sheet dismissed")
                            if (applePayResponse != nil) {
                                // Send to PSP via Relay on your backend
                            }
                            break
                        case let .failure(error):
                            print("Payment sheet error: \(error.localizedDescription)")
                            break
                        }
                    }
            } else {
                Text("Not available")
            }
        }
    }
}

#Preview {
    ContentView()
}
