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
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                AsyncImage(
                    url: URL(string: "https://c8.alamy.com/comp/BRH3DN/a-young-man-playing-a-trumpet-BRH3DN.jpg"),
                    content: { img in
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                    },
                    placeholder: {
                        ProgressView()
                    }
                )
                .frame(maxWidth: .infinity)
                .clipShape(Rectangle())
                .cornerRadius(8)
                
                // 2. Title
                Text("Evil Trumpet (man not included)")
                    .font(.title)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // 3. Description
                Text("A very annoying instrument")
                    .font(.body)
                    .multilineTextAlignment(.leading)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Specifications")
                        .font(.headline)
                    HStack {
                        Text("Overall Length:")
                        Spacer()
                        Text("48 cm")
                    }
                    HStack {
                        Text("Weight:")
                        Spacer()
                        Text("2.5 lb / 1.13 kg")
                    }
                    HStack {
                        Text("Can play:")
                        Spacer()
                        Text("Tequila")
                    }
                }
                .padding()
                .background(Color(.systemGroupedBackground))
                .cornerRadius(8)
                
                if let resp = pwResponse {
                    Text("Token: \(resp.networkToken.number)")
                    Text("Cryptogram: \(resp.cryptogram)")
                }
                
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
                    // buttonStyle: .whiteOutline,
                    // buttonType: .checkout,
                    authorizedResponse: $pwResponse,
                    onFinish: {
                        print("Payment sheet dismissed")
                    },
                    onError: { error in
                        print("Payment sheet error: \(String(describing: error))")
                    }
                )
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    ContentView()
}
