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

final class AuthorizationVerdictTests: XCTestCase {
    func testSuccessWhenAuthorizationSucceeded() {
        let verdict = EvervaultPaymentView.authorizationVerdict(for: .success(()))
        XCTAssertEqual(verdict, .success)
    }

    func testFailureAlreadyReportedWhenAuthorizationFailed() {
        let verdict = EvervaultPaymentView.authorizationVerdict(for: .failure(EvervaultError.ApplePayUnavailableError))
        XCTAssertEqual(verdict, .failureAlreadyReported)
    }

    func testFailureAlreadyReportedWhenDeclined() {
        // Declines carry the merchant's own error type, not an EvervaultError - the verdict doesn't
        // care about the concrete type, only that something was already reported.
        let verdict = EvervaultPaymentView.authorizationVerdict(for: .failure(TestDeclineReason()))
        XCTAssertEqual(verdict, .failureAlreadyReported)
    }

    func testCancelledWhenNoAuthorizationAttemptCompleted() {
        let verdict = EvervaultPaymentView.authorizationVerdict(for: nil)
        XCTAssertEqual(verdict, .cancelled)
    }
}

private final class SpyDelegate: EvervaultPaymentViewDelegate {
    private(set) var didFinishWithResultCalls: [Result<Void, EvervaultError>] = []
    private(set) var didDeclinePaymentCalls: [Error] = []

    func evervaultPaymentView(_ view: EvervaultPaymentView, didAuthorizePayment result: ApplePayResponse?) {}

    func evervaultPaymentView(_ view: EvervaultPaymentView, didFinishWithResult result: Result<Void, EvervaultError>) {
        didFinishWithResultCalls.append(result)
    }

    func evervaultPaymentView(_ view: EvervaultPaymentView, didDeclinePayment reason: Error) {
        didDeclinePaymentCalls.append(reason)
    }

    func reset() {
        didFinishWithResultCalls = []
        didDeclinePaymentCalls = []
    }
}

@MainActor
private func makeViewForDispositionTests(delegate: SpyDelegate) -> EvervaultPaymentView {
    let transaction = Transaction.oneOffPayment(try! OneOffPaymentTransaction(
        country: "IE",
        currency: "EUR",
        paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))]
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

    func testFailureNotifiesDidDeclinePaymentOnlyNotDidFinishWithResult() async {
        let spy = SpyDelegate()
        let view = makeViewForDispositionTests(delegate: spy)
        let reason = TestDeclineReason()

        let result = await view.handleAuthorizationDisposition(.failure(reason))

        XCTAssertEqual(result.status, .failure)
        // result.errors?.first isn't checked for its exact type here. 
        // PKPaymentAuthorizationResult is a PassKit type, and passing an error through it 
        // changes what type comes back out - so a type check here would fail 
        // even though we did pass a TestDeclineReason in.
        // The didDeclinePayment check below is the trustworthy one: it receives our error
        // directly, without going through PassKit at all.
        XCTAssertEqual(result.errors?.count, 1)
        XCTAssertEqual(spy.didDeclinePaymentCalls.count, 1)
        XCTAssertTrue(spy.didDeclinePaymentCalls.first is TestDeclineReason)
        XCTAssertTrue(spy.didFinishWithResultCalls.isEmpty)
    }
}
