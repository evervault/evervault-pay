//
//  ContentView.swift
//  Demo
//
//  Created by Jake Grogan on 12/06/2025.
//

import SwiftUI
import EvervaultPayment

fileprivate func buildTransaction(type: TransactionType) -> EvervaultPayment.Transaction {
    switch type {
    case .disbursement:
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
    case .oneOff:
        return try! .oneOffPayment(.init(
             country: "IE",
             currency: "EUR",
             paymentSummaryItems: [
                 SummaryItem(label: "Mens Shirt", amount: Amount("30.00")),
                 SummaryItem(label: "Socks", amount: Amount("5.00")),
                 SummaryItem(label: "Total", amount: Amount("35.00"))
             ]
         ))
    case .recurring:
        return try! .recurringPayment(.init(country: "IE", currency: "EUR", paymentSummaryItems: [
            SummaryItem(label: "Mens Shirt", amount: Amount("30.00")),
            SummaryItem(label: "Socks", amount: Amount("5.00")),
            SummaryItem(label: "Total", amount: Amount("35.00"))
        ], paymentDescription: "Orders a shirt and socks everry month", regularBilling: .init(label: "Checkout", amount: 70.0), managementURL: URL(string: "https://mock.evervault.com/checkout")!))
    }
}

enum TransactionType {
    case oneOff
    case recurring
    case disbursement
}

struct TransactionHandler : View {
    let name: String
    let type: TransactionType

    @State
    private var applePayResponse: ApplePayResponse? = nil
    private let transaction: EvervaultPayment.Transaction

    init(name: String, type: TransactionType) {
        self.name = name
        self.type = type
        self.transaction = buildTransaction(type: type)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(self.name)
            Spacer()
            if EvervaultPaymentViewRepresentable.isAvailable() {
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

struct ContentView: View {
    var body: some View {
        TabView {
            TransactionHandler(name: "One-Off", type: .oneOff)
                .tabItem {
                    Label("One-Off", systemImage: "house")
                }

            TransactionHandler(name: "Disbursement", type: .disbursement)
                .tabItem {
                    Label("Disbursement", systemImage: "magnifyingglass")
                }

            TransactionHandler(name: "Recurring", type: .recurring)
                .tabItem {
                    Label("Recurring", systemImage: "person.crop.circle")
                }
        }
    }
}

#Preview {
    ContentView()
}
