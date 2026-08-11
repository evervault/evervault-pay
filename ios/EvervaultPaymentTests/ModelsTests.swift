import XCTest
import Contacts
import PassKit
@testable import EvervaultPayment

final class ApplePayContactTests: XCTestCase {
    func testNilContactReturnsNil() {
        XCTAssertNil(ApplePayContact(nil))
    }

    func testMapsAllFieldsIncludingPhoneticNameAndAddress() {
        let contact = PKContact()

        var name = PersonNameComponents()
        name.givenName = "Taro"
        name.familyName = "Yamada"
        var phonetic = PersonNameComponents()
        phonetic.givenName = "たろう"
        phonetic.familyName = "やまだ"
        name.phoneticRepresentation = phonetic
        contact.name = name

        contact.emailAddress = "taro@example.com"
        contact.phoneNumber = CNPhoneNumber(stringValue: "+15555550100")

        let address = CNMutablePostalAddress()
        address.street = "1 Main St"
        address.city = "Dublin"
        address.state = "Leinster"
        address.postalCode = "D01"
        address.country = "Ireland"
        address.isoCountryCode = "IE"
        contact.postalAddress = address

        let result = ApplePayContact(contact)

        XCTAssertEqual(result?.givenName, "Taro")
        XCTAssertEqual(result?.familyName, "Yamada")
        XCTAssertEqual(result?.phoneticGivenName, "たろう")
        XCTAssertEqual(result?.phoneticFamilyName, "やまだ")
        XCTAssertEqual(result?.emailAddress, "taro@example.com")
        XCTAssertEqual(result?.phoneNumber, "+15555550100")
        XCTAssertEqual(result?.postalAddress?.street, "1 Main St")
        XCTAssertEqual(result?.postalAddress?.city, "Dublin")
        XCTAssertEqual(result?.postalAddress?.state, "Leinster")
        XCTAssertEqual(result?.postalAddress?.postalCode, "D01")
        XCTAssertEqual(result?.postalAddress?.country, "Ireland")
        XCTAssertEqual(result?.postalAddress?.isoCountryCode, "IE")
    }

    func testEmptyPhoneticNameCollapsesToNil() {
        let contact = PKContact()

        var name = PersonNameComponents()
        name.givenName = "Ana"
        name.familyName = "M"
        // Simulator's synthetic Apple Pay test contact hands back a non-nil
        // phoneticRepresentation with empty fields rather than nil outright.
        name.phoneticRepresentation = PersonNameComponents()
        contact.name = name

        let result = ApplePayContact(contact)

        XCTAssertEqual(result?.givenName, "Ana")
        XCTAssertEqual(result?.familyName, "M")
        XCTAssertNil(result?.phoneticGivenName)
        XCTAssertNil(result?.phoneticFamilyName)
    }

    func testEmptyNameEmailAndPhoneCollapseToNil() {
        let contact = PKContact()

        var name = PersonNameComponents()
        name.givenName = ""
        name.familyName = ""
        contact.name = name
        contact.emailAddress = ""
        contact.phoneNumber = CNPhoneNumber(stringValue: "")

        let result = ApplePayContact(contact)

        XCTAssertNil(result?.givenName)
        XCTAssertNil(result?.familyName)
        XCTAssertNil(result?.emailAddress)
        XCTAssertNil(result?.phoneNumber)
    }

    func testMissingFieldsMapToNil() {
        let contact = PKContact()
        contact.emailAddress = "only-email@example.com"

        let result = ApplePayContact(contact)

        XCTAssertEqual(result?.emailAddress, "only-email@example.com")
        XCTAssertNil(result?.givenName)
        XCTAssertNil(result?.familyName)
        XCTAssertNil(result?.phoneticGivenName)
        XCTAssertNil(result?.phoneticFamilyName)
        XCTAssertNil(result?.phoneNumber)
        XCTAssertNil(result?.postalAddress)
    }

    func testEmptyPostalAddressFieldsCollapseToNil() {
        let contact = PKContact()
        contact.postalAddress = CNMutablePostalAddress()

        let result = ApplePayContact(contact)

        XCTAssertNotNil(result?.postalAddress)
        XCTAssertNil(result?.postalAddress?.street)
        XCTAssertNil(result?.postalAddress?.city)
        XCTAssertNil(result?.postalAddress?.state)
        XCTAssertNil(result?.postalAddress?.postalCode)
        XCTAssertNil(result?.postalAddress?.country)
        XCTAssertNil(result?.postalAddress?.isoCountryCode)
    }
}

final class ApplePayTransactionTypeTests: XCTestCase {
    func testMapsOneOffPayment() throws {
        let transaction = Transaction.oneOffPayment(try OneOffPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))]
        ))

        XCTAssertEqual(ApplePayTransactionType(transaction), .oneOff)
    }

    func testMapsRecurringPayment() throws {
        let transaction = Transaction.recurringPayment(try RecurringPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentDescription: "Subscription",
            regularBilling: PKRecurringPaymentSummaryItem(label: "Monthly", amount: NSDecimalNumber(string: "10.00")),
            managementURL: URL(string: "https://example.com/manage")!
        ))

        XCTAssertEqual(ApplePayTransactionType(transaction), .recurring)
    }

    func testMapsDisbursement() throws {
        let transaction = Transaction.disbursement(try DisbursementTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            disbursementItem: SummaryItem(label: "Payout", amount: Amount("10.00")),
            requiredRecipientDetails: [],
            merchantCapability: .capability3DS
        ))

        XCTAssertEqual(ApplePayTransactionType(transaction), .disbursement)
    }
}

final class ApplePayResponseEnrichedTests: XCTestCase {
    private func makeBaseResponse() -> ApplePayResponse {
        ApplePayResponse(
            networkToken: ApplePayNetworkToken(
                number: "ev:abc",
                expiry: ApplePayNetworkTokenExpiry(month: 12, year: 30),
                rawExpiry: "12/30",
                tokenServiceProvider: "Apple"
            ),
            card: ApplePayCard(brand: "visa", funding: "debit", segment: "consumer", country: "ie", currency: "eur", issuer: "Bank"),
            cryptogram: "ev:cryptogram",
            eci: "5",
            paymentDataType: "3DSecure",
            deviceManufacturerIdentifier: "device-id",
            transactionId: "test-transaction-id-abc123"
        )
    }

    private func makeContact(givenName: String) -> PKContact {
        let contact = PKContact()
        var name = PersonNameComponents()
        name.givenName = givenName
        contact.name = name
        return contact
    }

    func testEnrichedPreservesBackendFieldsAndSetsNewOnes() {
        let base = makeBaseResponse()
        let billingContact = ApplePayContact(makeContact(givenName: "John"))
        let shippingContact = ApplePayContact(makeContact(givenName: "Jane"))

        let enriched = base.enriched(billingContact: billingContact, shippingContact: shippingContact, transactionType: .oneOff)

        XCTAssertEqual(enriched.networkToken, base.networkToken)
        XCTAssertEqual(enriched.card, base.card)
        XCTAssertEqual(enriched.cryptogram, base.cryptogram)
        XCTAssertEqual(enriched.eci, base.eci)
        XCTAssertEqual(enriched.paymentDataType, base.paymentDataType)
        XCTAssertEqual(enriched.deviceManufacturerIdentifier, base.deviceManufacturerIdentifier)
        XCTAssertEqual(enriched.transactionId, base.transactionId)

        XCTAssertNil(base.billingContact)
        XCTAssertNil(base.shippingContact)
        XCTAssertNil(base.transactionType)

        XCTAssertEqual(enriched.billingContact?.givenName, "John")
        XCTAssertEqual(enriched.shippingContact?.givenName, "Jane")
        XCTAssertEqual(enriched.transactionType, .oneOff)
    }

    func testEnrichedWithNilContactsKeepsThemNil() {
        let base = makeBaseResponse()

        let enriched = base.enriched(billingContact: nil, shippingContact: nil, transactionType: .disbursement)

        XCTAssertNil(enriched.billingContact)
        XCTAssertNil(enriched.shippingContact)
        XCTAssertEqual(enriched.transactionType, .disbursement)
    }
}

final class ApplePayResponseDecodingTests: XCTestCase {
    func testDecodesBackendJSONWithoutNewFields() throws {
        let json = """
        {
          "networkToken": {"number": "ev:abc", "expiry": {"month": "12", "year": "30"}, "rawExpiry": "12/30", "tokenServiceProvider": "Apple"},
          "card": {"brand": "visa"},
          "cryptogram": "ev:cryptogram",
          "eci": "5",
          "paymentDataType": "3DSecure",
          "deviceManufacturerIdentifier": "device-id"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ApplePayResponse.self, from: json)

        XCTAssertEqual(decoded.networkToken.number, "ev:abc")
        XCTAssertEqual(decoded.card.brand, "visa")
        XCTAssertNil(decoded.billingContact)
        XCTAssertNil(decoded.shippingContact)
        XCTAssertNil(decoded.transactionType)
        XCTAssertNil(decoded.transactionId)
    }

    func testDecodesTransactionIdWhenPresent() throws {
        let json = """
        {
          "networkToken": {"number": "ev:abc", "expiry": {"month": "12", "year": "30"}, "rawExpiry": "12/30", "tokenServiceProvider": "Apple"},
          "card": {"brand": "visa"},
          "cryptogram": "ev:cryptogram",
          "eci": "5",
          "paymentDataType": "3DSecure",
          "deviceManufacturerIdentifier": "device-id",
          "transactionId": "test-transaction-id-abc123"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(ApplePayResponse.self, from: json)

        XCTAssertEqual(decoded.transactionId, "test-transaction-id-abc123")
    }
}

final class ApplePayAvailabilityTests: XCTestCase {
    func testUnsupportedWhenDeviceCannotMakePayments() {
        let availability = EvervaultPaymentView.evaluateAvailability(deviceSupportsApplePay: false, hasCardForSupportedNetworks: false)
        XCTAssertEqual(availability, .unsupported)
    }

    func testUnsupportedWhenDeviceCannotMakePaymentsEvenIfNetworksMatch() {
        let availability = EvervaultPaymentView.evaluateAvailability(deviceSupportsApplePay: false, hasCardForSupportedNetworks: true)
        XCTAssertEqual(availability, .unsupported)
    }

    func testUnavailableWhenDeviceSupportsButHasNoProvisionedCard() {
        let availability = EvervaultPaymentView.evaluateAvailability(deviceSupportsApplePay: true, hasCardForSupportedNetworks: false)
        XCTAssertEqual(availability, .unavailable)
    }

    func testAvailableWhenDeviceSupportsAndHasProvisionedCard() {
        let availability = EvervaultPaymentView.evaluateAvailability(deviceSupportsApplePay: true, hasCardForSupportedNetworks: true)
        XCTAssertEqual(availability, .available)
    }
}

private struct TestDeclineReason: Error {}
private struct TestNetworkError: Error {}

final class ResolveDispositionTests: XCTestCase {
    func testSuccessDispositionMapsToSuccessOutcome() {
        let outcome = EvervaultPaymentView.resolveDisposition(for: .success(()))
        XCTAssertNoThrow(try outcome.get())
    }

    func testFailureDispositionMapsToMerchantDeclinedError() {
        let reason = TestDeclineReason()
        let outcome = EvervaultPaymentView.resolveDisposition(for: .failure(reason))

        XCTAssertThrowsError(try outcome.get()) { error in
            XCTAssertEqual(error.localizedDescription, "Merchant declined the payment: \(reason.localizedDescription)")
        }
    }
}

private final class SpyDelegate: EvervaultPaymentViewDelegate {
    private(set) var didFinishWithResultCalls: [Result<Void, EvervaultError>] = []
    private(set) var didDeclinePaymentCalls: [Error] = []
    private(set) var didCancelCallCount = 0
    /// Lets a test await an async-dispatched delegate call instead of racing it.
    var didReportExpectation: XCTestExpectation?
    /// Lets a test control what `didChangeCouponCode` returns; nil (the default) exercises the SDK's fallback.
    var didChangeCouponCodeHandler: ((String) -> PKPaymentRequestCouponCodeUpdate?)?

    func evervaultPaymentView(_ view: EvervaultPaymentView, didAuthorizePayment result: ApplePayResponse?) {}

    func evervaultPaymentView(_ view: EvervaultPaymentView, didChangeCouponCode couponCode: String) async -> PKPaymentRequestCouponCodeUpdate? {
        return didChangeCouponCodeHandler?(couponCode)
    }

    func evervaultPaymentView(_ view: EvervaultPaymentView, didFinishWithResult result: Result<Void, EvervaultError>) {
        didFinishWithResultCalls.append(result)
        didReportExpectation?.fulfill()
    }

    func evervaultPaymentView(_ view: EvervaultPaymentView, didDeclinePayment reason: Error) {
        didDeclinePaymentCalls.append(reason)
        didReportExpectation?.fulfill()
    }

    func evervaultPaymentViewDidCancel(_ view: EvervaultPaymentView) {
        didCancelCallCount += 1
        didReportExpectation?.fulfill()
    }

    func reset() {
        didFinishWithResultCalls = []
        didDeclinePaymentCalls = []
        didCancelCallCount = 0
    }
}

@MainActor
private func makeViewForDispositionTests(
    delegate: SpyDelegate,
    paymentSummaryItems: [SummaryItem] = [SummaryItem(label: "Total", amount: Amount("10.00"))]
) -> EvervaultPaymentView {
    let transaction = Transaction.oneOffPayment(try! OneOffPaymentTransaction(
        country: "IE",
        currency: "EUR",
        paymentSummaryItems: paymentSummaryItems
    ))
    let view = EvervaultPaymentView(
        appId: "test-app-id",
        appleMerchantId: "merchant.test",
        transaction: transaction,
        supportedNetworks: [.visa],
        buttonStyle: .automatic,
        buttonType: .buy
    )
    view.delegate = delegate
    // On a simulator/host with no Wallet cards, wiring up the delegate immediately fires
    // didFinishWithResult(.ApplePayUnavailableError) - unrelated to what these tests check.
    // Reset here so the spy starts clean before the actual test logic runs.
    delegate.reset()
    return view
}

@MainActor
final class HandleAuthorizationDispositionTests: XCTestCase {
    func testSuccessDoesNotNotifyDelegateAndReturnsSuccessResult() async {
        let spy = SpyDelegate()
        let view = makeViewForDispositionTests(delegate: spy)

        let result = await view.handleAuthorizationDisposition(.success(()))

        XCTAssertEqual(result.status, .success)
        XCTAssertTrue(spy.didFinishWithResultCalls.isEmpty)
        XCTAssertTrue(spy.didDeclinePaymentCalls.isEmpty)
    }

    func testFailureDoesNotNotifyDelegateAndReturnsFailureResult() async {
        let spy = SpyDelegate()
        let view = makeViewForDispositionTests(delegate: spy)
        let reason = TestDeclineReason()

        let result = await view.handleAuthorizationDisposition(.failure(reason))

        XCTAssertEqual(result.status, .failure)
        XCTAssertEqual(result.errors?.count, 1)
        // Deferred to paymentAuthorizationViewControllerDidFinish.
        XCTAssertTrue(spy.didDeclinePaymentCalls.isEmpty)
        XCTAssertTrue(spy.didFinishWithResultCalls.isEmpty)
    }
}

@MainActor
final class HandleAuthorizationFailureTests: XCTestCase {
    func testDoesNotNotifyDelegateAndReturnsFailureResult() async {
        let spy = SpyDelegate()
        let view = makeViewForDispositionTests(delegate: spy)

        let result = await view.handleAuthorizationFailure(TestNetworkError())

        XCTAssertEqual(result.status, .failure)
        XCTAssertEqual(result.errors?.count, 1)
        // Deferred to paymentAuthorizationViewControllerDidFinish.
        XCTAssertTrue(spy.didFinishWithResultCalls.isEmpty)
        XCTAssertTrue(spy.didDeclinePaymentCalls.isEmpty)
    }
}

@MainActor
private func makeAuthorizationController() -> PKPaymentAuthorizationViewController {
    let request = PKPaymentRequest()
    request.merchantIdentifier = "merchant.test"
    request.supportedNetworks = [.visa]
    request.countryCode = "IE"
    request.currencyCode = "EUR"
    request.paymentSummaryItems = [PKPaymentSummaryItem(label: "Total", amount: NSDecimalNumber(string: "10.00"))]
    request.merchantCapabilities = .threeDSecure
    return PKPaymentAuthorizationViewController(paymentRequest: request)!
}

/// Proves reporting happens only from `paymentAuthorizationViewControllerDidFinish`,
/// not from `handleAuthorizationDisposition`/`handleAuthorizationFailure`.
@MainActor
final class PaymentAuthorizationViewControllerDidFinishTests: XCTestCase {
    func testDeclineFiresOnlyAfterDidFinishNotAfterHandleDisposition() async {
        let spy = SpyDelegate()
        let view = makeViewForDispositionTests(delegate: spy)
        let reason = TestDeclineReason()

        _ = await view.handleAuthorizationDisposition(.failure(reason))
        XCTAssertTrue(spy.didDeclinePaymentCalls.isEmpty, "must not fire before the sheet finishes")

        let reported = expectation(description: "didDeclinePayment reported")
        spy.didReportExpectation = reported
        view.paymentAuthorizationViewControllerDidFinish(makeAuthorizationController())
        await fulfillment(of: [reported], timeout: 1)

        XCTAssertEqual(spy.didDeclinePaymentCalls.count, 1)
        XCTAssertTrue(spy.didDeclinePaymentCalls.first is TestDeclineReason)
        XCTAssertTrue(spy.didFinishWithResultCalls.isEmpty)
    }

    func testSdkFailureFiresOnlyAfterDidFinishNotAfterHandleFailure() async {
        let spy = SpyDelegate()
        let view = makeViewForDispositionTests(delegate: spy)

        _ = await view.handleAuthorizationFailure(TestNetworkError())
        XCTAssertTrue(spy.didFinishWithResultCalls.isEmpty, "must not fire before the sheet finishes")

        let reported = expectation(description: "didFinishWithResult reported")
        spy.didReportExpectation = reported
        view.paymentAuthorizationViewControllerDidFinish(makeAuthorizationController())
        await fulfillment(of: [reported], timeout: 1)

        XCTAssertEqual(spy.didFinishWithResultCalls.count, 1)
        XCTAssertThrowsError(try XCTUnwrap(spy.didFinishWithResultCalls.first).get())
        XCTAssertTrue(spy.didDeclinePaymentCalls.isEmpty)
    }

    func testSuccessReportsAfterDidFinish() async {
        let spy = SpyDelegate()
        let view = makeViewForDispositionTests(delegate: spy)

        _ = await view.handleAuthorizationDisposition(.success(()))
        XCTAssertTrue(spy.didFinishWithResultCalls.isEmpty, "must not fire before the sheet finishes")

        let reported = expectation(description: "didFinishWithResult reported")
        spy.didReportExpectation = reported
        view.paymentAuthorizationViewControllerDidFinish(makeAuthorizationController())
        await fulfillment(of: [reported], timeout: 1)

        XCTAssertEqual(spy.didFinishWithResultCalls.count, 1)
        XCTAssertNoThrow(try XCTUnwrap(spy.didFinishWithResultCalls.first).get())
        XCTAssertTrue(spy.didDeclinePaymentCalls.isEmpty)
    }

    func testCancelReportsWhenNoAuthorizationAttemptEverCompleted() async {
        let spy = SpyDelegate()
        let view = makeViewForDispositionTests(delegate: spy)

        // No handler ran, so tapAuthorizationOutcome stays nil.
        let reported = expectation(description: "evervaultPaymentViewDidCancel reported")
        spy.didReportExpectation = reported
        view.paymentAuthorizationViewControllerDidFinish(makeAuthorizationController())
        await fulfillment(of: [reported], timeout: 1)

        XCTAssertEqual(spy.didCancelCallCount, 1)
        XCTAssertTrue(spy.didFinishWithResultCalls.isEmpty)
        XCTAssertTrue(spy.didDeclinePaymentCalls.isEmpty)
    }
}

@MainActor
final class CouponCodeDelegateTests: XCTestCase {
    func testReturnsDelegateProvidedUpdateWhenImplemented() async {
        let spy = SpyDelegate()
        let view = makeViewForDispositionTests(delegate: spy)
        let expectedUpdate = PKPaymentRequestCouponCodeUpdate(
            paymentSummaryItems: [PKPaymentSummaryItem(label: "Total (discounted)", amount: NSDecimalNumber(string: "8.00"))]
        )
        spy.didChangeCouponCodeHandler = { couponCode in
            XCTAssertEqual(couponCode, "SAVE20")
            return expectedUpdate
        }

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didChangeCouponCode: "SAVE20")

        // Same instance the delegate returned - proves it's a straight passthrough.
        XCTAssertTrue(result === expectedUpdate)
    }

    func testFallsBackToCurrentSummaryItemsWhenDelegateReturnsNil() async {
        let spy = SpyDelegate()
        let view = makeViewForDispositionTests(delegate: spy)
        // didChangeCouponCodeHandler left unset - matches an unimplemented (default) delegate method.

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didChangeCouponCode: "SAVE20")

        // Falls back to the transaction's existing summary items, set up in makeViewForDispositionTests.
        XCTAssertEqual(result.paymentSummaryItems.map(\.label), ["Total"])
        XCTAssertEqual(result.paymentSummaryItems.map(\.amount), [NSDecimalNumber(string: "10.00")])
    }

    func testFallsBackToAllCurrentSummaryItemsWhenMultipleLineItemsExist() async {
        let spy = SpyDelegate()
        let view = makeViewForDispositionTests(delegate: spy, paymentSummaryItems: [
            SummaryItem(label: "Mens Shirt", amount: Amount("30.00")),
            SummaryItem(label: "Socks", amount: Amount("5.00")),
            SummaryItem(label: "Total", amount: Amount("35.00"))
        ])

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didChangeCouponCode: "SAVE20")

        XCTAssertEqual(result.paymentSummaryItems.map(\.label), ["Mens Shirt", "Socks", "Total"])
        XCTAssertEqual(result.paymentSummaryItems.map(\.amount), [
            NSDecimalNumber(string: "30.00"),
            NSDecimalNumber(string: "5.00"),
            NSDecimalNumber(string: "35.00")
        ])
    }
}
