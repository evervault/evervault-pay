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

/// Standard Shipping costs less to Ireland than everywhere else; Express is a flat rate.
fileprivate func makeShippingMethods(countryCode: String?) -> [PKShippingMethod] {
    let standard = PKShippingMethod(label: "Standard Shipping", amount: NSDecimalNumber(string: countryCode == "IE" ? "0.00" : "2.99"))
    standard.identifier = "standard"
    standard.detail = "Delivered in 5-7 business days"

    let express = PKShippingMethod(label: "Express Shipping", amount: NSDecimalNumber(string: "9.99"))
    express.identifier = "express"
    express.detail = "Delivered in 1-2 business days"

    return [standard, express]
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
            merchantCapability: .instantFundsOut,
            applicationData: Data("payout_456".utf8)
        ))
    case .oneOff:
        return try! .oneOffPayment(.init(
             country: "IE",
             currency: "EUR",
             paymentSummaryItems: [
                 SummaryItem(label: "Mens Shirt", amount: Amount("30.00")),
                 SummaryItem(label: "Socks", amount: Amount("5.00")),
                 SummaryItem(label: "Estimated Tax", amount: Amount("2.50"), type: .pending),
                 SummaryItem(label: "Total", amount: Amount("37.50"))
             ],
             shippingType: .shipping,
             shippingMethods: makeShippingMethods(countryCode: nil),
             requiredShippingContactFields: [.postalAddress, .name, .emailAddress, .phoneNumber],
             requestPayerDetails: [.postalAddress, .name, .emailAddress, .phoneNumber],
             supportsCouponCode: true,
             billingContact: makeSampleBillingContact(),
             shippingContact: makeSampleShippingContact(),
             applicationData: Data("order_123".utf8),
             supportedCountries: ["IE", "GB", "US"]
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
            billingAgreement: "https://www.merchant.com/billing-agreement",
            requestPayerDetails: [.postalAddress, .name, .emailAddress, .phoneNumber],
            billingContact: makeSampleBillingContact(),
            shippingType: .shipping,
            requiredShippingContactFields: [.postalAddress, .name, .emailAddress, .phoneNumber],
            shippingContact: makeSampleShippingContact(),
            applicationData: Data("order_123".utf8),
            supportedCountries: ["IE", "GB", "US"]
        )
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
            billingAgreement: "https://www.merchant.com/billing-agreement",
            requestPayerDetails: [.postalAddress, .name, .emailAddress, .phoneNumber],
            billingContact: makeSampleBillingContact(),
            shippingContact: makeSampleShippingContact()
        )
        return .automaticReload(automaticReloadRequest)
    case .deferred:
        let deferredBilling = PKDeferredPaymentSummaryItem(
            label: "Remaining Balance",
            amount: NSDecimalNumber(string: "150.00")
        )
        var deferredDateComponent = DateComponents()
        deferredDateComponent.day = 30
        deferredBilling.deferredDate = Calendar.current.date(byAdding: deferredDateComponent, to: Date())!

        var freeCancellationDateComponent = DateComponents()
        freeCancellationDateComponent.day = 7
        let freeCancellationDate = Calendar.current.date(byAdding: freeCancellationDateComponent, to: Date())!

        let deferredRequest = try! DeferredPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [
                SummaryItem(label: "Hotel Reservation Deposit", amount: Amount("50.00"))
            ],
            paymentDescription: "Hotel reservation deposit example.",
            deferredBilling: deferredBilling,
            managementURL: URL(string: "https://www.merchant.com/manage-reservation")!,
            billingAgreement: "https://www.merchant.com/billing-agreement",
            freeCancellationDate: freeCancellationDate,
            freeCancellationDateTimeZone: TimeZone(identifier: "Europe/Dublin"),
            requestPayerDetails: [.postalAddress, .name, .emailAddress, .phoneNumber],
            billingContact: makeSampleBillingContact(),
            shippingContact: makeSampleShippingContact()
        )
        return .deferredPayment(deferredRequest)
    }
}

/// Tracks the buyer's in-progress choices on the sheet so any one change (address, coupon,
/// shipping method) can be applied on top of the others instead of overwriting them.
fileprivate struct CheckoutCart {
    var shippingCountryCode: String? = nil
    var appliedCouponCode: String? = nil
    var shippingMethod: PKShippingMethod? = nil
}

fileprivate extension Array where Element == SummaryItem {
    func asPKSummaryItems() -> [PKPaymentSummaryItem] {
        map { PKPaymentSummaryItem(label: $0.label, amount: $0.amount.amount, type: $0.type) }
    }
}

/// Rebuilds One-Off's summary items from the transaction's pristine base items plus every
/// choice currently on `cart`, so applying one doesn't drop the others.
fileprivate func buildOneOffSummaryItems(_ oneOff: OneOffPaymentTransaction, cart: CheckoutCart) -> [SummaryItem] {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2

    var items = oneOff.paymentSummaryItems
    _ = items.popLast() // drop the pristine "Total"; recomputed below

    if let method = cart.shippingMethod {
        items.append(SummaryItem(label: method.label, amount: Amount(formatter.string(from: method.amount) ?? method.amount.stringValue)))
    }

    var subtotal = items.map { $0.amount.amount as Decimal }.reduce(Decimal.zero, +)

    if cart.appliedCouponCode?.uppercased() == "SAVE20" {
        let discount = subtotal * Decimal(0.2)
        items.append(SummaryItem(label: "Discount (SAVE20)", amount: Amount("-" + (formatter.string(from: discount as NSDecimalNumber) ?? discount.description))))
        subtotal -= discount
    }

    items.append(SummaryItem(label: "Total", amount: Amount(formatter.string(from: subtotal as NSDecimalNumber) ?? subtotal.description)))
    return items
}

/// Demo rule: 20% off (coupon) then +10% surcharge outside Ireland (address), both from `cart`.
fileprivate func recurringRegularBilling(base: PKRecurringPaymentSummaryItem, cart: CheckoutCart) -> PKRecurringPaymentSummaryItem {
    let isDiscounted = cart.appliedCouponCode?.uppercased() == "SAVE20"
    let isInternational = cart.shippingCountryCode != "IE"

    var amount = base.amount as Decimal
    var label = base.label
    if isDiscounted {
        amount *= Decimal(0.8)
        label += " (20% off)"
    }
    if isInternational {
        amount *= Decimal(1.1)
        label += " (international surcharge)"
    }

    let billing = PKRecurringPaymentSummaryItem(label: label, amount: NSDecimalNumber(decimal: amount))
    billing.intervalUnit = base.intervalUnit
    billing.intervalCount = base.intervalCount
    billing.startDate = base.startDate
    billing.endDate = base.endDate
    return billing
}

fileprivate func getShippingAddressUpdate(_ newAddress: ShippingContact, cart: inout CheckoutCart, transaction: EvervaultPayment.Transaction) -> PKPaymentRequestShippingContactUpdate {
    cart.shippingCountryCode = newAddress.postalAddress?.isoCountryCode

    switch transaction {
    case .oneOffPayment(let oneOff):
        let items = buildOneOffSummaryItems(oneOff, cart: cart)
        return PKPaymentRequestShippingContactUpdate(
            errors: nil,
            paymentSummaryItems: items.asPKSummaryItems(),
            shippingMethods: makeShippingMethods(countryCode: cart.shippingCountryCode)
        )

    case .disbursement(let disbursement):
        var summaryItems = disbursement.paymentSummaryItems
        if disbursement.merchantCapability == .instantFundsOut,
           let instantOutFee = disbursement.instantOutFee {
            summaryItems.append(instantOutFee)
        }
        summaryItems.append(disbursement.disbursementItem)
        return PKPaymentRequestShippingContactUpdate(
            errors: nil,
            paymentSummaryItems: summaryItems.asPKSummaryItems(),
            shippingMethods: []
        )

    case .recurringPayment(let recurring):
        let regularBilling = recurringRegularBilling(base: recurring.regularBilling, cart: cart)

        var items = recurring.paymentSummaryItems.asPKSummaryItems()
        items.append(regularBilling)
        if let trial = recurring.trialBilling { items.append(trial) }

        let update = PKPaymentRequestShippingContactUpdate(errors: nil, paymentSummaryItems: items, shippingMethods: [])

        let recurringRequest = PKRecurringPaymentRequest(
            paymentDescription: recurring.paymentDescription,
            regularBilling: regularBilling,
            managementURL: recurring.managementURL
        )
        recurringRequest.trialBilling = recurring.trialBilling
        recurringRequest.billingAgreement = recurring.billingAgreement
        update.recurringPaymentRequest = recurringRequest
        return update

    case .automaticReload(let automaticReload):
        let automaticReloadBilling = PKAutomaticReloadPaymentSummaryItem(
            label: automaticReload.automaticReloadBilling.label,
            amount: automaticReload.automaticReloadBilling.amount.amount
        )
        if let threshold = automaticReload.automaticReloadThresholdAmount {
            automaticReloadBilling.thresholdAmount = threshold.amount
        }

        var items = automaticReload.paymentSummaryItems.asPKSummaryItems()
        items.append(automaticReloadBilling)

        let update = PKPaymentRequestShippingContactUpdate(errors: nil, paymentSummaryItems: items, shippingMethods: [])

        let automaticReloadRequest = PKAutomaticReloadPaymentRequest(
            paymentDescription: automaticReload.paymentDescription,
            automaticReloadBilling: automaticReloadBilling,
            managementURL: automaticReload.managementURL
        )
        automaticReloadRequest.billingAgreement = automaticReload.billingAgreement
        update.automaticReloadPaymentRequest = automaticReloadRequest
        return update

    case .deferredPayment(let deferred):
        let deferredBilling = PKDeferredPaymentSummaryItem(
            label: deferred.deferredBilling.label,
            amount: deferred.deferredBilling.amount
        )
        deferredBilling.deferredDate = deferred.deferredBilling.deferredDate

        var items = deferred.paymentSummaryItems.asPKSummaryItems()
        items.append(deferredBilling)

        let update = PKPaymentRequestShippingContactUpdate(errors: nil, paymentSummaryItems: items, shippingMethods: [])

        let deferredRequest = PKDeferredPaymentRequest(
            paymentDescription: deferred.paymentDescription,
            deferredBilling: deferredBilling,
            managementURL: deferred.managementURL
        )
        deferredRequest.billingAgreement = deferred.billingAgreement
        deferredRequest.tokenNotificationURL = deferred.tokenNotificationURL
        deferredRequest.freeCancellationDate = deferred.freeCancellationDate
        deferredRequest.freeCancellationDateTimeZone = deferred.freeCancellationDateTimeZone
        update.deferredPaymentRequest = deferredRequest
        return update
    }
}

/// Example coupon handling: "SAVE20" takes 20% off, anything else is rejected via PassKit's own
/// invalid-coupon error. Not wired up for disbursement transactions (payouts, not purchases).
fileprivate func getCouponCodeUpdate(_ couponCode: String, cart: inout CheckoutCart, transaction: EvervaultPayment.Transaction) -> PKPaymentRequestCouponCodeUpdate {
    let isValid = couponCode.uppercased() == "SAVE20"
    cart.appliedCouponCode = isValid ? couponCode : nil
    let invalidCodeError = PKPaymentRequest.paymentCouponCodeInvalidError(localizedDescription: "That coupon code isn't valid.")

    switch transaction {
    case .oneOffPayment(let oneOff):
        let summaryItems = buildOneOffSummaryItems(oneOff, cart: cart).asPKSummaryItems()

        guard isValid else {
            return PKPaymentRequestCouponCodeUpdate(errors: [invalidCodeError], paymentSummaryItems: summaryItems, shippingMethods: [])
        }
        return PKPaymentRequestCouponCodeUpdate(paymentSummaryItems: summaryItems)

    case .recurringPayment(let recurring):
        let regularBilling = recurringRegularBilling(base: recurring.regularBilling, cart: cart)

        var items = recurring.paymentSummaryItems.asPKSummaryItems()
        items.append(regularBilling)
        if let trial = recurring.trialBilling { items.append(trial) }

        let recurringRequest = PKRecurringPaymentRequest(
            paymentDescription: recurring.paymentDescription,
            regularBilling: regularBilling,
            managementURL: recurring.managementURL
        )
        recurringRequest.trialBilling = recurring.trialBilling
        recurringRequest.billingAgreement = recurring.billingAgreement

        let update = isValid
            ? PKPaymentRequestCouponCodeUpdate(paymentSummaryItems: items)
            : PKPaymentRequestCouponCodeUpdate(errors: [invalidCodeError], paymentSummaryItems: items, shippingMethods: [])
        // PassKit treats nil as "no change" for recurring payments, so this is set unconditionally -
        // otherwise an outdated discount/surcharge could silently stick around after a rejection.
        update.recurringPaymentRequest = recurringRequest
        return update

    case .disbursement:
        return PKPaymentRequestCouponCodeUpdate(paymentSummaryItems: [])

    case .automaticReload:
        // Coupon codes aren't the primary use case for a wallet top-up, so no discount logic here.
        return PKPaymentRequestCouponCodeUpdate(paymentSummaryItems: [])

    case .deferredPayment:
        // Coupon codes aren't the primary use case for a booking deposit, so no discount logic here.
        return PKPaymentRequestCouponCodeUpdate(paymentSummaryItems: [])
    }
}

/// Example shipping-method handling: recomputes the total to include the selected method's cost.
/// Not wired up for recurring/disbursement/automaticReload/deferredPayment transactions - shipping
/// methods are only modeled for one-off purchases.
fileprivate func getShippingMethodUpdate(_ shippingMethod: PKShippingMethod, cart: inout CheckoutCart, transaction: EvervaultPayment.Transaction) -> PKPaymentRequestShippingMethodUpdate {
    cart.shippingMethod = shippingMethod

    switch transaction {
    case .oneOffPayment(let oneOff):
        let items = buildOneOffSummaryItems(oneOff, cart: cart)
        return PKPaymentRequestShippingMethodUpdate(paymentSummaryItems: items.asPKSummaryItems())

    case .recurringPayment(let recurring):
        return PKPaymentRequestShippingMethodUpdate(paymentSummaryItems: recurring.paymentSummaryItems.asPKSummaryItems())

    case .disbursement(let disbursement):
        return PKPaymentRequestShippingMethodUpdate(paymentSummaryItems: disbursement.paymentSummaryItems.asPKSummaryItems())

    case .automaticReload(let automaticReload):
        return PKPaymentRequestShippingMethodUpdate(paymentSummaryItems: automaticReload.paymentSummaryItems.asPKSummaryItems())

    case .deferredPayment(let deferred):
        return PKPaymentRequestShippingMethodUpdate(paymentSummaryItems: deferred.paymentSummaryItems.asPKSummaryItems())
    }
}

enum TransactionType {
    case oneOff
    case recurring
    case disbursement
    case automaticReload
    case deferred
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
    @State
    private var cart = CheckoutCart()
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
                        getShippingAddressUpdate(newAddress, cart: &cart, transaction: self.transaction)
                    }.onCouponCodeChange { couponCode in
                        getCouponCodeUpdate(couponCode, cart: &cart, transaction: self.transaction)
                    }.onShippingMethodChange { shippingMethod in
                        getShippingMethodUpdate(shippingMethod, cart: &cart, transaction: self.transaction)
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

            TransactionHandler(name: "Deferred Payment", type: .deferred)
                .tabItem {
                    Label("Deferred Payment", systemImage: "calendar.badge.clock")
                }
        }
    }
}

#Preview {
    ContentView()
}
