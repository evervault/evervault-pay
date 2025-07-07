//
//  ContentView.swift
//  Demo
//
//  Created by Jake Grogan on 12/06/2025.
//

import SwiftUI
import EvervaultPayment

func buildTransaction() -> EvervaultPayment.Transaction {
        let transaction = try! EvervaultPayment.Transaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [
                SummaryItem(label: "Mens Shirt", amount: Amount("30.00")),
                SummaryItem(label: "Socks", amount: Amount("5.00")),
                SummaryItem(label: "Total", amount: Amount("35.00"))
            ]
        )
        return transaction
}

struct ContentView: View {
    @State private var applePayResponse: ApplePayResponse? = nil
    let transaction = buildTransaction()
    
    var body: some View {
        VStack(spacing: 20) {
            EvervaultPaymentViewRepresentable(
                appUuid: "YOUR_EVERVAULT_APP_ID",
                merchantIdentifier: "YOUR_APPLE_MERCHANT_ID",
                transaction: transaction,
                supportedNetworks: [.visa, .masterCard, .amex],
                buttonStyle: .whiteOutline,
                buttonType: .checkout,
                authorizedResponse: $applePayResponse,
                onFinish: {
                    print("Payment sheet dismissed")
                },
                onError: { error in
                    let message = error?.localizedDescription
                    print("Payment sheet error: \(String(describing: message))")
                }
            )
        }
    }
}

#Preview {
    ContentView()
}
