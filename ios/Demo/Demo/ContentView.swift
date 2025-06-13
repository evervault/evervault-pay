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
        VStack(alignment: .center, spacing: 10) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            Spacer()
            EvervaultPaymentViewRepresentable(
                merchantIdentifier: "merchant.com.example",
                transaction: try! Transaction(
                  country: "US",
                  currency: "USD",
                  paymentSummaryItems: [
                    SummaryItem(label: "Test", amount: Amount("1.00"))
                  ]
                ),
                supportedNetworks: [EvervaultPayment.Network.visa, .masterCard, .amex],
                authorizedResponse: $pwResponse,
                onFinish: {
                  print("Payment sheet dismissed")
                }
            )

            if let resp = pwResponse {
                Text("Auth cryptogram: \(resp.cryptogram)")
            }
    }
        .padding()
    }
}

#Preview {
    ContentView()
}
