//
//  ContentView.swift
//  Demo
//
//  Created by Jake Grogan on 12/06/2025.
//

import SwiftUI
import EvervaultPayment

func buildTransaction() -> EvervaultPayment.Transaction? {
    do {
        let transaction = try EvervaultPayment.Transaction(
            country: "US",
            currency: "USD",
            paymentSummaryItems: [
                SummaryItem(label: "Test Item", amount: Amount("10.00"))
            ]
        )
        return transaction
    } catch {
        print("error")
    }
    return nil
}

struct ContentView: View {
    @State private var pwResponse: ApplePayResponse? = nil
    let transaction = buildTransaction()
    
    var body: some View {
        VStack {
            Text("Hello World")
            Spacer()
            EvervaultPaymentViewRepresentable(
                appUuid: "app_1234567890",
                merchantIdentifier: "merchant.com.example",
                transaction: try! Transaction(
                    country: "US",
                    currency: "USD",
                    paymentSummaryItems: [
                        SummaryItem(label: "Evil Trumpet", amount: Amount("90.00")),
                        SummaryItem(label: "Trumpet Case", amount: Amount("10.00")),
                        SummaryItem(label: "Total", amount: Amount("100.00"))
                    ]
                ),
                supportedNetworks: [EvervaultPayment.Network.visa, .masterCard, .amex],
                authorizedResponse: $pwResponse,
                onFinish: {
                    print("Payment sheet dismissed")
                }
            )
        }
    }
}

#Preview {
    ContentView()
}
