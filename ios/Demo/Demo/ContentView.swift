//
//  ContentView.swift
//  Demo
//
//  Created by Jake Grogan on 12/06/2025.
//

import SwiftUI
import EvervaultPayment
import PassKit

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
            merchantCapability: .instantFundsOut
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
        let express = ShippingMethod(
          label: "Express Shipping",                      // what shows in the UI
          amount: NSDecimalNumber(string: "9.99")         // cost
        )
        express.identifier = "express_1day"
        express.detail = "Arrives in 1–2 business days."
        
        let standard = ShippingMethod(
            label: "Standard Shipping",
            amount: NSDecimalNumber(string: "2.99")
        )
        standard.identifier = "standard_3day"
        standard.detail = "Arrives in 3-5 business days."
        
        let recurringBilling = PKRecurringPaymentSummaryItem(
            label: "Pro Subscription",
            amount: 5.00
        )
        recurringBilling.intervalUnit = .month
        recurringBilling.intervalCount = 2
        var dateComponent = DateComponents()
        dateComponent.day = 7
        recurringBilling.startDate = Calendar.current.date(byAdding: dateComponent, to: Date())
        
        let trialBilling = PKRecurringPaymentSummaryItem(label: "Trial", amount: 0)
        trialBilling.startDate = nil // Now
        
        var recurringBillingRequest = try! RecurringPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [],
            paymentDescription: "Recurring payment example.",
            regularBilling: recurringBilling,
            managementURL: URL(string: "https://www.merchant.com/manage-subscriptions")!
        )
        recurringBillingRequest.billingAgreement = "https://www.merchant.com/billing-agreement"
        recurringBillingRequest.trialBilling = trialBilling
        return .recurringPayment(recurringBillingRequest)
    }
}

fileprivate func getUpdatedTransaction(_ newAddress: ShippingContact, transaction: EvervaultPayment.Transaction) -> [SummaryItem] {
    // Get the country for the new address
    let country = newAddress.postalAddress?.country
    
    // Calculate the shipping cost based on the new address
    let shippingCost = country == "IE" ? Amount("2.99") : Amount("9.99")

    switch transaction {
    case .oneOffPayment(let oneOff):
        var summaryItems = [SummaryItem(label: "Shipping", amount: shippingCost)] + oneOff.paymentSummaryItems

        // Remove the old "Total" line item
        _ = summaryItems.popLast()

        // Calculate the new total
        let newTotal = summaryItems
            .map { $0.amount.amount as Decimal }
            .reduce(Decimal.zero, +)
        
        // Format for currency
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formattedTotal = formatter.string(
            from: newTotal as NSDecimalNumber
        ) ?? newTotal.description
        
        // Add the new "Total" line item to the end
        summaryItems.append(
            SummaryItem(label: "Total", amount: Amount(formattedTotal))
        )

        return summaryItems
    case .disbursement(let disbursement):
        // Calculate new line items and total for address change
        return disbursement.paymentSummaryItems
    case .recurringPayment(let recurring):
        // Calculate new line items and total for address change
        var summaryItems = [SummaryItem(label: "Shipping", amount: shippingCost)]
        summaryItems = summaryItems + recurring.paymentSummaryItems
        
        // Calculate the new total
        let newTotal = summaryItems
            .map { $0.amount.amount as Decimal }
            .reduce(Decimal.zero, +)
        
        // Format for currency
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let formattedTotal = formatter.string(
            from: newTotal as NSDecimalNumber
        ) ?? newTotal.description
        
        // Add the new "Total" line item to the end
        summaryItems.append(
            SummaryItem(label: "Total", amount: Amount(formattedTotal))
        )

        return summaryItems
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
                    .onShippingAddressChange { newAddress in
                        return getUpdatedTransaction(newAddress, transaction: self.transaction)
                    }.prepareTransaction { transaction in
                        print("Preparing transaction")
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
