//
//  ContentView.swift
//  Demo
//
//  Created by Jake Grogan on 12/06/2025.
//

import SwiftUI
import EvervaultPayment
import PassKit

// Sample prefill contacts, exercising the new `ApplePayPaymentContact` billing/shipping prefill.
// PassKit only surfaces the postal-address portion if `.postalAddress` is also in the
// matching `required...ContactFields` set below - see `ApplePayPaymentContact`'s doc comment.
fileprivate func makeSampleBillingContact() -> ApplePayPaymentContact {
    ApplePayPaymentContact(
        givenName: "Harry",
        familyName: "Potter",
        emailAddress: "harry.potter@hogwarts.edu",
        phoneNumber: "+442079460958",
        addressLines: ["4 Privet Drive"],
        locality: "Little Whinging",
        postalCode: "GU21 5RH",
        administrativeArea: "Surrey",
        country: "United Kingdom",
        countryCode: "GB"
    )
}

fileprivate func makeSampleShippingContact() -> ApplePayPaymentContact {
    ApplePayPaymentContact(
        givenName: "Hermione",
        familyName: "Granger",
        emailAddress: "hermione.granger@hogwarts.edu",
        phoneNumber: "+442079460321",
        addressLines: ["Hogwarts School of Witchcraft and Wizardry"],
        locality: "Hogsmeade",
        postalCode: "HG1 1SW",
        administrativeArea: "Scottish Highlands",
        country: "United Kingdom",
        countryCode: "GB"
    )
}

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
             ],
             shippingType: .shipping,
             shippingMethods: [],
             requiredShippingContactFields: [.postalAddress, .name, .emailAddress, .phoneNumber],
             requestPayerDetails: [.postalAddress, .name, .emailAddress, .phoneNumber],
             supportsCouponCode: true,
             billingContact: makeSampleBillingContact(),
             shippingContact: makeSampleShippingContact()
         ))
    case .recurring:
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
            managementURL: URL(string: "https://www.merchant.com/manage-subscriptions")!,
            requestPayerDetails: [.postalAddress, .name, .emailAddress, .phoneNumber],
            billingContact: makeSampleBillingContact(),
            shippingType: .shipping,
            requiredShippingContactFields: [.postalAddress, .name, .emailAddress, .phoneNumber],
            shippingContact: makeSampleShippingContact()
        )
        recurringBillingRequest.billingAgreement = "https://www.merchant.com/billing-agreement"
        recurringBillingRequest.trialBilling = trialBilling
        recurringBillingRequest.supportsCouponCode = true
        return .recurringPayment(recurringBillingRequest)
    case .automaticReload:
        let automaticReloadRequest = try! AutomaticReloadPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentDescription: "Automatic reload example.",
            automaticReloadBilling: SummaryItem(label: "Wallet Top-Up", amount: Amount("20.00")),
            automaticReloadThresholdAmount: Amount("5.00"),
            managementURL: URL(string: "https://www.merchant.com/manage-wallet")!,
            requestPayerDetails: [.postalAddress, .name, .emailAddress, .phoneNumber],
            billingContact: makeSampleBillingContact(),
            shippingContact: makeSampleShippingContact()
        )
        return .automaticReload(automaticReloadRequest)
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
        return recurring.paymentSummaryItems
    case .automaticReload(let automaticReload):
        return automaticReload.paymentSummaryItems
    }
}

/// Example coupon handling: "SAVE20" takes 20% off, anything else is rejected via PassKit's own
/// invalid-coupon error. Not wired up for disbursement transactions (payouts, not purchases).
fileprivate func getCouponCodeUpdate(_ couponCode: String, transaction: EvervaultPayment.Transaction) -> PKPaymentRequestCouponCodeUpdate {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2

    switch transaction {
    case .oneOffPayment(let oneOff):
        var summaryItems = oneOff.paymentSummaryItems
        // Remove the old "Total" line item; we'll recompute and re-append it below.
        _ = summaryItems.popLast()

        guard couponCode.uppercased() == "SAVE20" else {
            let subtotal = summaryItems.map { $0.amount.amount as Decimal }.reduce(Decimal.zero, +)
            summaryItems.append(SummaryItem(label: "Total", amount: Amount(formatter.string(from: subtotal as NSDecimalNumber) ?? subtotal.description)))

            return PKPaymentRequestCouponCodeUpdate(
                errors: [PKPaymentRequest.paymentCouponCodeInvalidError(localizedDescription: "That coupon code isn't valid.")],
                paymentSummaryItems: summaryItems.map { PKPaymentSummaryItem(label: $0.label, amount: $0.amount.amount) },
                shippingMethods: []
            )
        }

        let subtotal = summaryItems.map { $0.amount.amount as Decimal }.reduce(Decimal.zero, +)
        let discount = subtotal * Decimal(0.2)
        let discountedTotal = subtotal - discount

        summaryItems.append(SummaryItem(label: "Discount (SAVE20)", amount: Amount("-" + (formatter.string(from: discount as NSDecimalNumber) ?? discount.description))))
        summaryItems.append(SummaryItem(label: "Total", amount: Amount(formatter.string(from: discountedTotal as NSDecimalNumber) ?? discountedTotal.description)))

        return PKPaymentRequestCouponCodeUpdate(
            paymentSummaryItems: summaryItems.map { PKPaymentSummaryItem(label: $0.label, amount: $0.amount.amount) }
        )

    case .recurringPayment(let recurring):
        // Rebuilds the recurring request around a given regularBilling, preserving everything
        // else (billing agreement, trial, management URL) - used below for both the discounted
        // and undiscounted cases.
        func recurringRequest(regularBilling: PKRecurringPaymentSummaryItem) -> PKRecurringPaymentRequest {
            let request = PKRecurringPaymentRequest(
                paymentDescription: recurring.paymentDescription,
                regularBilling: regularBilling,
                managementURL: recurring.managementURL
            )
            request.trialBilling = recurring.trialBilling
            request.billingAgreement = recurring.billingAgreement
            return request
        }

        var items = recurring.paymentSummaryItems.map { PKPaymentSummaryItem(label: $0.label, amount: $0.amount.amount) }

        guard couponCode.uppercased() == "SAVE20" else {
            items.append(recurring.regularBilling)
            if let trial = recurring.trialBilling { items.append(trial) }

            let update = PKPaymentRequestCouponCodeUpdate(
                errors: [PKPaymentRequest.paymentCouponCodeInvalidError(localizedDescription: "That coupon code isn't valid.")],
                paymentSummaryItems: items,
                shippingMethods: []
            )
            // PassKit treats nil as "no change" for recurring payments. Reset explicitly to
            // prevent an outdated discount from silently sticking around.
            update.recurringPaymentRequest = recurringRequest(regularBilling: recurring.regularBilling)
            return update
        }

        // Deduct the discount from every billing cycle by replacing regularBilling itself -
        // a flat one-off summary line wouldn't affect what's actually charged on future cycles.
        let discountedAmount = (recurring.regularBilling.amount as Decimal) * Decimal(0.8)
        let discountedBilling = PKRecurringPaymentSummaryItem(
            label: recurring.regularBilling.label + " (20% off)",
            amount: NSDecimalNumber(decimal: discountedAmount)
        )
        discountedBilling.intervalUnit = recurring.regularBilling.intervalUnit
        discountedBilling.intervalCount = recurring.regularBilling.intervalCount
        discountedBilling.startDate = recurring.regularBilling.startDate
        discountedBilling.endDate = recurring.regularBilling.endDate

        items.append(discountedBilling)
        if let trial = recurring.trialBilling { items.append(trial) }

        let update = PKPaymentRequestCouponCodeUpdate(paymentSummaryItems: items)
        update.recurringPaymentRequest = recurringRequest(regularBilling: discountedBilling)
        return update

    case .disbursement:
        return PKPaymentRequestCouponCodeUpdate(paymentSummaryItems: [])

    case .automaticReload:
        // Coupon codes aren't the primary use case for a wallet top-up, so no discount logic here.
        return PKPaymentRequestCouponCodeUpdate(paymentSummaryItems: [])
    }
}

enum TransactionType {
    case oneOff
    case recurring
    case disbursement
    case automaticReload
}

// Example merchant-owned error type, passed to `shouldAuthorize`'s `.failure(_:)`.
// Since it's just an `Error`, the merchant's own downstream code can `switch` over it exhaustively.
enum DeclineReason: Error, LocalizedError {
    case prepaidCardNotAccepted

    var errorDescription: String? {
        switch self {
        case .prepaidCardNotAccepted:
            return "Prepaid cards are not accepted"
        }
    }
}

struct TransactionHandler : View {
    let name: String
    let type: TransactionType

    @State
    private var applePayResponse: ApplePayResponse? = nil
    @State
    private var errorMessage: String? = nil
    private let transaction: EvervaultPayment.Transaction

    init(name: String, type: TransactionType) {
        self.name = name
        self.type = type
        self.transaction = buildTransaction(type: type)
    }

    private let supportedNetworks: [Network] = [.visa, .masterCard, .amex]

    private var isShowingError: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { isPresented in if !isPresented { errorMessage = nil } }
        )
    }

    var body: some View {
        let availability = EvervaultPaymentViewRepresentable.availability(supportedNetworks: supportedNetworks)

        VStack(spacing: 20) {
            Text(self.name)
            Spacer()
            if availability != .unsupported {
                EvervaultPaymentViewRepresentable(
                    appId: "YOUR_EVERVAULT_APP_ID",
                    appleMerchantId: "YOUR_APPLE_MERCHANT_ID",
                    transaction: self.transaction,
                    supportedNetworks: supportedNetworks,
                    buttonStyle: .whiteOutline,
                    // No provisioned card yet: prompt the user to set one up instead of a normal buy button.
                    buttonType: availability == .unavailable ? .setUp : .checkout,
                    authorizedResponse: $applePayResponse) { result in
                        switch result {
                        case .success(_):
                            print("Payment sheet dismissed with success")
                            if (applePayResponse != nil) {
                                // Send to PSP via Relay on your backend
                            }
                            break
                        case let .failure(error):
                            print("Payment sheet error: \(error.localizedDescription)")
                            errorMessage = error.localizedDescription
                            break
                        }
                    }
                    .onShippingAddressChange { newAddress in
                        return getUpdatedTransaction(newAddress, transaction: self.transaction)
                    }.onCouponCodeChange { couponCode in
                        return getCouponCodeUpdate(couponCode, transaction: self.transaction)
                    }.prepareTransaction { transaction in
                        print("Preparing transaction")
                    }.onCancel {
                        print("Payment sheet cancelled")
                    }.onDecline { reason in
                        print("Payment declined: \(reason.localizedDescription)")
                        errorMessage = reason.localizedDescription
                    }.shouldAuthorize { response in
                        // Example merchant rule: reject prepaid cards.
                        if response?.card.funding == "prepaid" {
                            return .failure(DeclineReason.prepaidCardNotAccepted)
                        }
                        return .success(())
                    }
            } else {
                Text("Not available")
            }
        }
        .alert("Payment Failed", isPresented: isShowingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "")
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

            TransactionHandler(name: "Automatic Reload", type: .automaticReload)
                .tabItem {
                    Label("Automatic Reload", systemImage: "arrow.clockwise")
                }
        }
    }
}

#Preview {
    ContentView()
}
