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

final class ApplePayPaymentContactToPKContactTests: XCTestCase {
    func testMapsAllFieldsIncludingAddress() {
        let contact = ApplePayPaymentContact(
            givenName: "Taro",
            familyName: "Yamada",
            phoneticGivenName: "たろう",
            phoneticFamilyName: "やまだ",
            emailAddress: "taro@example.com",
            phoneNumber: "+15555550100",
            addressLines: ["1 Main St", "Apt 2"],
            subLocality: "Ranelagh",
            locality: "Dublin",
            postalCode: "D01",
            subAdministrativeArea: "Dublin County",
            administrativeArea: "Leinster",
            country: "Ireland",
            countryCode: "IE"
        )

        let result = PKContact(contact)

        XCTAssertEqual(result.name?.givenName, "Taro")
        XCTAssertEqual(result.name?.familyName, "Yamada")
        XCTAssertEqual(result.name?.phoneticRepresentation?.givenName, "たろう")
        XCTAssertEqual(result.name?.phoneticRepresentation?.familyName, "やまだ")
        XCTAssertEqual(result.emailAddress, "taro@example.com")
        XCTAssertEqual(result.phoneNumber?.stringValue, "+15555550100")
        XCTAssertEqual(result.postalAddress?.street, "1 Main St\nApt 2")
        XCTAssertEqual(result.postalAddress?.subLocality, "Ranelagh")
        XCTAssertEqual(result.postalAddress?.city, "Dublin")
        XCTAssertEqual(result.postalAddress?.postalCode, "D01")
        XCTAssertEqual(result.postalAddress?.subAdministrativeArea, "Dublin County")
        XCTAssertEqual(result.postalAddress?.state, "Leinster")
        XCTAssertEqual(result.postalAddress?.country, "Ireland")
        XCTAssertEqual(result.postalAddress?.isoCountryCode, "IE")
    }

    func testNoNameFieldsProducesNilName() {
        let contact = ApplePayPaymentContact(emailAddress: "only-email@example.com")

        let result = PKContact(contact)

        XCTAssertNil(result.name)
        XCTAssertEqual(result.emailAddress, "only-email@example.com")
    }

    func testNameWithoutPhoneticFieldsOmitsPhoneticRepresentation() {
        let contact = ApplePayPaymentContact(givenName: "Ana", familyName: "M")

        let result = PKContact(contact)

        XCTAssertEqual(result.name?.givenName, "Ana")
        XCTAssertEqual(result.name?.familyName, "M")
        XCTAssertNil(result.name?.phoneticRepresentation)
    }

    func testNoAddressFieldsProducesNilPostalAddress() {
        let contact = ApplePayPaymentContact(emailAddress: "only-email@example.com")

        let result = PKContact(contact)

        XCTAssertNil(result.postalAddress)
    }

    func testAddressLinesOnlyStillBuildsAddress() {
        let contact = ApplePayPaymentContact(addressLines: ["1 Main St"])

        let result = PKContact(contact)

        XCTAssertEqual(result.postalAddress?.street, "1 Main St")
        XCTAssertEqual(result.postalAddress?.city, "")
        XCTAssertEqual(result.postalAddress?.state, "")
        XCTAssertEqual(result.postalAddress?.postalCode, "")
        XCTAssertEqual(result.postalAddress?.country, "")
        XCTAssertEqual(result.postalAddress?.isoCountryCode, "")
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

final class SummaryItemTests: XCTestCase {
    func testDefaultsTypeToFinal() {
        let item = SummaryItem(label: "Total", amount: Amount("10.00"))

        XCTAssertEqual(item.type, .final)
    }

    func testStoresProvidedType() {
        let item = SummaryItem(label: "Shipping", amount: Amount("5.00"), type: .pending)

        XCTAssertEqual(item.type, .pending)
    }
}

final class TransactionPrefillFieldsTests: XCTestCase {
    private func makeBillingContact() -> ApplePayPaymentContact {
        ApplePayPaymentContact(givenName: "John", familyName: "Doe")
    }

    private func makeShippingContact() -> ApplePayPaymentContact {
        ApplePayPaymentContact(givenName: "Jane", familyName: "Doe")
    }

    func testOneOffDefaultsBillingAndShippingContactToNil() throws {
        let transaction = try OneOffPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))]
        )

        XCTAssertNil(transaction.billingContact)
        XCTAssertNil(transaction.shippingContact)
    }

    func testOneOffStoresProvidedBillingAndShippingContact() throws {
        let transaction = try OneOffPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            billingContact: makeBillingContact(),
            shippingContact: makeShippingContact()
        )

        XCTAssertEqual(transaction.billingContact?.givenName, "John")
        XCTAssertEqual(transaction.shippingContact?.givenName, "Jane")
    }

    func testRecurringDefaultsBillingContactAndShippingFieldsToNilOrEmpty() throws {
        let transaction = try RecurringPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentDescription: "Subscription",
            regularBilling: PKRecurringPaymentSummaryItem(label: "Monthly", amount: NSDecimalNumber(string: "10.00")),
            managementURL: URL(string: "https://example.com/manage")!
        )

        XCTAssertNil(transaction.billingContact)
        XCTAssertNil(transaction.shippingContact)
        XCTAssertEqual(transaction.shippingType, .shipping)
        XCTAssertTrue(transaction.requiredShippingContactFields.isEmpty)
    }

    func testRecurringStoresProvidedBillingShippingAndShippingFields() throws {
        let transaction = try RecurringPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentDescription: "Subscription",
            regularBilling: PKRecurringPaymentSummaryItem(label: "Monthly", amount: NSDecimalNumber(string: "10.00")),
            managementURL: URL(string: "https://example.com/manage")!,
            billingContact: makeBillingContact(),
            shippingType: .delivery,
            requiredShippingContactFields: [.postalAddress],
            shippingContact: makeShippingContact()
        )

        XCTAssertEqual(transaction.billingContact?.givenName, "John")
        XCTAssertEqual(transaction.shippingContact?.givenName, "Jane")
        XCTAssertEqual(transaction.shippingType, .delivery)
        XCTAssertEqual(transaction.requiredShippingContactFields, [.postalAddress])
    }
}

final class TransactionRequestPassthroughFieldsTests: XCTestCase {
    private let applicationData = "hello".data(using: .utf8)!

    func testOneOffDefaultsApplicationDataToNil() throws {
        let transaction = try OneOffPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))]
        )

        XCTAssertNil(transaction.applicationData)
    }

    func testOneOffDefaultsSupportedCountriesToNil() throws {
        let transaction = try OneOffPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))]
        )

        XCTAssertNil(transaction.supportedCountries)
    }

    func testOneOffStoresProvidedApplicationData() throws {
        let transaction = try OneOffPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            applicationData: applicationData
        )

        XCTAssertEqual(transaction.applicationData, applicationData)
    }

    func testOneOffStoresProvidedSupportedCountries() throws {
        let transaction = try OneOffPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            supportedCountries: ["IE", "GB"]
        )

        XCTAssertEqual(transaction.supportedCountries, ["IE", "GB"])
    }

    @available(iOS 16, *)
    func testOneOffLocaleInitStoresProvidedApplicationData() throws {
        let transaction = try OneOffPaymentTransaction(
            country: Locale.Region("IE"),
            currency: Locale.Currency("EUR"),
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            applicationData: applicationData
        )

        XCTAssertEqual(transaction.applicationData, applicationData)
    }

    @available(iOS 16, *)
    func testOneOffLocaleInitStoresProvidedSupportedCountries() throws {
        let transaction = try OneOffPaymentTransaction(
            country: Locale.Region("IE"),
            currency: Locale.Currency("EUR"),
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            supportedCountries: ["IE", "GB"]
        )

        XCTAssertEqual(transaction.supportedCountries, ["IE", "GB"])
    }

    func testRecurringDefaultsApplicationDataToNil() throws {
        let transaction = try RecurringPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentDescription: "Subscription",
            regularBilling: PKRecurringPaymentSummaryItem(label: "Monthly", amount: NSDecimalNumber(string: "10.00")),
            managementURL: URL(string: "https://example.com/manage")!
        )

        XCTAssertNil(transaction.applicationData)
    }

    func testRecurringDefaultsSupportedCountriesToNil() throws {
        let transaction = try RecurringPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentDescription: "Subscription",
            regularBilling: PKRecurringPaymentSummaryItem(label: "Monthly", amount: NSDecimalNumber(string: "10.00")),
            managementURL: URL(string: "https://example.com/manage")!
        )

        XCTAssertNil(transaction.supportedCountries)
    }

    func testRecurringStoresProvidedApplicationData() throws {
        let transaction = try RecurringPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentDescription: "Subscription",
            regularBilling: PKRecurringPaymentSummaryItem(label: "Monthly", amount: NSDecimalNumber(string: "10.00")),
            managementURL: URL(string: "https://example.com/manage")!,
            applicationData: applicationData
        )

        XCTAssertEqual(transaction.applicationData, applicationData)
    }

    func testRecurringStoresProvidedSupportedCountries() throws {
        let transaction = try RecurringPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentDescription: "Subscription",
            regularBilling: PKRecurringPaymentSummaryItem(label: "Monthly", amount: NSDecimalNumber(string: "10.00")),
            managementURL: URL(string: "https://example.com/manage")!,
            supportedCountries: ["IE", "GB"]
        )

        XCTAssertEqual(transaction.supportedCountries, ["IE", "GB"])
    }

    func testDisbursementDefaultsApplicationDataToNil() throws {
        let transaction = try DisbursementTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            disbursementItem: SummaryItem(label: "Payout", amount: Amount("10.00")),
            requiredRecipientDetails: [],
            merchantCapability: .capability3DS
        )

        XCTAssertNil(transaction.applicationData)
    }

    func testDisbursementStoresProvidedApplicationData() throws {
        let transaction = try DisbursementTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            disbursementItem: SummaryItem(label: "Payout", amount: Amount("10.00")),
            requiredRecipientDetails: [],
            merchantCapability: .capability3DS,
            applicationData: applicationData
        )

        XCTAssertEqual(transaction.applicationData, applicationData)
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

        let enriched = base.enriched(billingContact: billingContact, shippingContact: shippingContact, transactionType: .oneOff, displayName: "Visa 1234")

        XCTAssertEqual(enriched.networkToken, base.networkToken)
        XCTAssertEqual(enriched.cryptogram, base.cryptogram)
        XCTAssertEqual(enriched.eci, base.eci)
        XCTAssertEqual(enriched.paymentDataType, base.paymentDataType)
        XCTAssertEqual(enriched.deviceManufacturerIdentifier, base.deviceManufacturerIdentifier)
        XCTAssertEqual(enriched.transactionId, base.transactionId)

        XCTAssertEqual(enriched.card.brand, base.card.brand)
        XCTAssertEqual(enriched.card.funding, base.card.funding)
        XCTAssertEqual(enriched.card.segment, base.card.segment)
        XCTAssertEqual(enriched.card.country, base.card.country)
        XCTAssertEqual(enriched.card.currency, base.card.currency)
        XCTAssertEqual(enriched.card.issuer, base.card.issuer)

        XCTAssertNil(base.billingContact)
        XCTAssertNil(base.shippingContact)
        XCTAssertNil(base.transactionType)
        XCTAssertNil(base.card.displayName)
        XCTAssertNil(base.card.lastFour)

        XCTAssertEqual(enriched.billingContact?.givenName, "John")
        XCTAssertEqual(enriched.shippingContact?.givenName, "Jane")
        XCTAssertEqual(enriched.transactionType, .oneOff)
        XCTAssertEqual(enriched.card.displayName, "Visa 1234")
        XCTAssertEqual(enriched.card.lastFour, "1234")
    }

    func testEnrichedWithNilContactsKeepsThemNil() {
        let base = makeBaseResponse()

        let enriched = base.enriched(billingContact: nil, shippingContact: nil, transactionType: .disbursement, displayName: nil)

        XCTAssertNil(enriched.billingContact)
        XCTAssertNil(enriched.shippingContact)
        XCTAssertEqual(enriched.transactionType, .disbursement)
    }

    func testEnrichedWithNilDisplayNameLeavesCardDisplayFieldsNil() {
        let base = makeBaseResponse()

        let enriched = base.enriched(billingContact: nil, shippingContact: nil, transactionType: .oneOff, displayName: nil)

        XCTAssertNil(enriched.card.displayName)
        XCTAssertNil(enriched.card.lastFour)
    }
}

final class ExtractLastFourTests: XCTestCase {
    func testMatchesTrailingFourDigits() {
        XCTAssertEqual(extractLastFour(from: "Visa 1234"), "1234")
    }

    func testReturnsNilWhenNoDigitsPresent() {
        XCTAssertNil(extractLastFour(from: "Visa"))
    }

    func testReturnsNilWhenDigitsAreNotAtTheEnd() {
        XCTAssertNil(extractLastFour(from: "1234 Visa"))
    }

    func testReturnsNilForNilInput() {
        XCTAssertNil(extractLastFour(from: nil))
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
    /// Lets a test control what `didSelectShippingContact` returns; nil (the default) exercises the SDK's fallback.
    var didSelectShippingContactHandler: ((PKContact) -> PKPaymentRequestShippingContactUpdate?)?
    /// Lets a test control what `didUpdatePaymentMethod` returns; nil (the default) exercises the SDK's fallback.
    var didUpdatePaymentMethodHandler: ((PKPaymentMethod) -> PKPaymentRequestPaymentMethodUpdate?)?
    /// Lets a test control what `didSelectShippingMethod` returns; nil (the default) exercises the SDK's fallback.
    var didSelectShippingMethodHandler: ((PKShippingMethod) -> PKPaymentRequestShippingMethodUpdate?)?

    func evervaultPaymentView(_ view: EvervaultPaymentView, didAuthorizePayment result: ApplePayResponse?) {}

    func evervaultPaymentView(_ view: EvervaultPaymentView, didChangeCouponCode couponCode: String) async -> PKPaymentRequestCouponCodeUpdate? {
        return didChangeCouponCodeHandler?(couponCode)
    }

    func evervaultPaymentView(_ view: EvervaultPaymentView, didSelectShippingContact contact: PKContact) async -> PKPaymentRequestShippingContactUpdate? {
        return didSelectShippingContactHandler?(contact)
    }

    func evervaultPaymentView(_ view: EvervaultPaymentView, didUpdatePaymentMethod paymentMethod: PKPaymentMethod) async -> PKPaymentRequestPaymentMethodUpdate? {
        return didUpdatePaymentMethodHandler?(paymentMethod)
    }

    func evervaultPaymentView(_ view: EvervaultPaymentView, didSelectShippingMethod shippingMethod: PKShippingMethod) async -> PKPaymentRequestShippingMethodUpdate? {
        return didSelectShippingMethodHandler?(shippingMethod)
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
    paymentSummaryItems: [SummaryItem] = [SummaryItem(label: "Total", amount: Amount("10.00"))],
    transaction: Transaction? = nil
) -> EvervaultPaymentView {
    let resolvedTransaction = transaction ?? .oneOffPayment(try! OneOffPaymentTransaction(
        country: "IE",
        currency: "EUR",
        paymentSummaryItems: paymentSummaryItems
    ))
    let view = EvervaultPaymentView(
        appId: "test-app-id",
        appleMerchantId: "merchant.test",
        transaction: resolvedTransaction,
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

    // Regression test: regularBilling and trialBilling are stored on the model as the real
    // PassKit types (no reconstruction needed), so it's easy for the fallback to forget to
    // append them too - which is exactly what happens today.
    func testFallsBackToSummaryItemsIncludingRegularAndTrialBillingForRecurringPayment() async throws {
        let spy = SpyDelegate()
        let transaction = Transaction.recurringPayment(try RecurringPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            paymentDescription: "Subscription",
            regularBilling: PKRecurringPaymentSummaryItem(label: "Monthly", amount: NSDecimalNumber(string: "9.99")),
            managementURL: URL(string: "https://example.com/manage")!
        ))
        let view = makeViewForDispositionTests(delegate: spy, transaction: transaction)
        // didChangeCouponCodeHandler left unset - exercises the SDK's getPaymentSummaryItems() fallback.

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didChangeCouponCode: "SAVE20")

        XCTAssertEqual(result.paymentSummaryItems.map(\.label), ["Total", "Monthly"])
        XCTAssertEqual(result.paymentSummaryItems.map(\.amount), [
            NSDecimalNumber(string: "10.00"),
            NSDecimalNumber(string: "9.99")
        ])
    }

    func testFallsBackToSummaryItemsIncludingTrialBillingWhenSetForRecurringPayment() async throws {
        let spy = SpyDelegate()
        var recurringTransaction = try RecurringPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            paymentDescription: "Subscription",
            regularBilling: PKRecurringPaymentSummaryItem(label: "Monthly", amount: NSDecimalNumber(string: "9.99")),
            managementURL: URL(string: "https://example.com/manage")!
        )
        recurringTransaction.trialBilling = PKRecurringPaymentSummaryItem(label: "Free Trial", amount: NSDecimalNumber(string: "0.00"))
        let view = makeViewForDispositionTests(delegate: spy, transaction: .recurringPayment(recurringTransaction))
        // didChangeCouponCodeHandler left unset - exercises the SDK's getPaymentSummaryItems() fallback.

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didChangeCouponCode: "SAVE20")

        XCTAssertEqual(result.paymentSummaryItems.map(\.label), ["Total", "Monthly", "Free Trial"])
        XCTAssertEqual(result.paymentSummaryItems.map(\.amount), [
            NSDecimalNumber(string: "10.00"),
            NSDecimalNumber(string: "9.99"),
            NSDecimalNumber(string: "0.00")
        ])
    }

    // Regression test: disbursementItem is stored on the model as a plain SummaryItem (reconstructed
    // into a PKDisbursementSummaryItem in buildPaymentRequest), so it's easy for the fallback to
    // forget to append it too - which is exactly what happens today.
    func testFallsBackToSummaryItemsIncludingDisbursementItemForDisbursement() async throws {
        let spy = SpyDelegate()
        let transaction = Transaction.disbursement(try DisbursementTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            disbursementItem: SummaryItem(label: "Payout", amount: Amount("10.00")),
            requiredRecipientDetails: [],
            merchantCapability: .capability3DS
        ))
        let view = makeViewForDispositionTests(delegate: spy, transaction: transaction)
        // didChangeCouponCodeHandler left unset - exercises the SDK's getPaymentSummaryItems() fallback.

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didChangeCouponCode: "SAVE20")

        XCTAssertEqual(result.paymentSummaryItems.map(\.label), ["Total", "Payout"])
        XCTAssertEqual(result.paymentSummaryItems.map(\.amount), [
            NSDecimalNumber(string: "10.00"),
            NSDecimalNumber(string: "10.00")
        ])
    }

    @available(iOS 17.0, *)
    func testFallsBackToSummaryItemsIncludingInstantOutFeeForInstantFundsOutDisbursement() async throws {
        let spy = SpyDelegate()
        let transaction = Transaction.disbursement(try DisbursementTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            disbursementItem: SummaryItem(label: "Payout", amount: Amount("10.00")),
            instantOutFee: SummaryItem(label: "Instant funds out fee", amount: Amount("1.00")),
            requiredRecipientDetails: [],
            merchantCapability: .instantFundsOut
        ))
        let view = makeViewForDispositionTests(delegate: spy, transaction: transaction)
        // didChangeCouponCodeHandler left unset - exercises the SDK's getPaymentSummaryItems() fallback.

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didChangeCouponCode: "SAVE20")

        XCTAssertEqual(result.paymentSummaryItems.map(\.label), ["Total", "Instant funds out fee", "Payout"])
        XCTAssertEqual(result.paymentSummaryItems.map(\.amount), [
            NSDecimalNumber(string: "10.00"),
            NSDecimalNumber(string: "1.00"),
            NSDecimalNumber(string: "10.00")
        ])
    }
}

@MainActor
final class ShippingContactDelegateTests: XCTestCase {
    func testReturnsDelegateProvidedUpdateWhenImplemented() async {
        let spy = SpyDelegate()
        let view = makeViewForDispositionTests(delegate: spy)
        let expectedUpdate = PKPaymentRequestShippingContactUpdate(
            paymentSummaryItems: [PKPaymentSummaryItem(label: "Total (shipping)", amount: NSDecimalNumber(string: "12.00"))]
        )
        spy.didSelectShippingContactHandler = { _ in expectedUpdate }

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didSelectShippingContact: PKContact())

        // Same instance the delegate returned - proves it's a straight passthrough.
        XCTAssertTrue(result === expectedUpdate)
    }

    // Regression coverage: getPaymentSummaryItems() is shared across all three PassKit fallback
    // entry points, but CouponCodeDelegateTests only exercises it via didChangeCouponCode. This
    // proves didSelectShippingContact is wired to the same (fixed) method.
    func testFallsBackToSummaryItemsIncludingRegularBillingForRecurringPayment() async throws {
        let spy = SpyDelegate()
        let transaction = Transaction.recurringPayment(try RecurringPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            paymentDescription: "Subscription",
            regularBilling: PKRecurringPaymentSummaryItem(label: "Monthly", amount: NSDecimalNumber(string: "9.99")),
            managementURL: URL(string: "https://example.com/manage")!
        ))
        let view = makeViewForDispositionTests(delegate: spy, transaction: transaction)
        // didSelectShippingContactHandler left unset - exercises the SDK's getPaymentSummaryItems() fallback.

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didSelectShippingContact: PKContact())

        XCTAssertEqual(result.paymentSummaryItems.map(\.label), ["Total", "Monthly"])
        XCTAssertEqual(result.paymentSummaryItems.map(\.amount), [
            NSDecimalNumber(string: "10.00"),
            NSDecimalNumber(string: "9.99")
        ])
    }

    // Same rationale as above, covering the other transaction type that appends an item.
    func testFallsBackToSummaryItemsIncludingDisbursementItemForDisbursement() async throws {
        let spy = SpyDelegate()
        let transaction = Transaction.disbursement(try DisbursementTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            disbursementItem: SummaryItem(label: "Payout", amount: Amount("10.00")),
            requiredRecipientDetails: [],
            merchantCapability: .capability3DS
        ))
        let view = makeViewForDispositionTests(delegate: spy, transaction: transaction)
        // didSelectShippingContactHandler left unset - exercises the SDK's getPaymentSummaryItems() fallback.

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didSelectShippingContact: PKContact())

        XCTAssertEqual(result.paymentSummaryItems.map(\.label), ["Total", "Payout"])
        XCTAssertEqual(result.paymentSummaryItems.map(\.amount), [
            NSDecimalNumber(string: "10.00"),
            NSDecimalNumber(string: "10.00")
        ])
    }
}

@MainActor
final class PaymentMethodDelegateTests: XCTestCase {
    func testReturnsDelegateProvidedUpdateWhenImplemented() async {
        let spy = SpyDelegate()
        let view = makeViewForDispositionTests(delegate: spy)
        let expectedUpdate = PKPaymentRequestPaymentMethodUpdate(
            paymentSummaryItems: [PKPaymentSummaryItem(label: "Total (payment method)", amount: NSDecimalNumber(string: "11.00"))]
        )
        spy.didUpdatePaymentMethodHandler = { _ in expectedUpdate }

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didSelect: PKPaymentMethod())

        XCTAssertTrue(result === expectedUpdate)
    }

    // Regression coverage: same rationale as ShippingContactDelegateTests above, but proving
    // didSelect paymentMethod's wiring specifically.
    func testFallsBackToSummaryItemsIncludingDisbursementItemForDisbursement() async throws {
        let spy = SpyDelegate()
        let transaction = Transaction.disbursement(try DisbursementTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            disbursementItem: SummaryItem(label: "Payout", amount: Amount("10.00")),
            requiredRecipientDetails: [],
            merchantCapability: .capability3DS
        ))
        let view = makeViewForDispositionTests(delegate: spy, transaction: transaction)
        // didUpdatePaymentMethodHandler left unset - exercises the SDK's getPaymentSummaryItems() fallback.

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didSelect: PKPaymentMethod())

        XCTAssertEqual(result.paymentSummaryItems.map(\.label), ["Total", "Payout"])
        XCTAssertEqual(result.paymentSummaryItems.map(\.amount), [
            NSDecimalNumber(string: "10.00"),
            NSDecimalNumber(string: "10.00")
        ])
    }

    // Same rationale as above, covering the other transaction type that appends an item.
    func testFallsBackToSummaryItemsIncludingRegularBillingForRecurringPayment() async throws {
        let spy = SpyDelegate()
        let transaction = Transaction.recurringPayment(try RecurringPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            paymentDescription: "Subscription",
            regularBilling: PKRecurringPaymentSummaryItem(label: "Monthly", amount: NSDecimalNumber(string: "9.99")),
            managementURL: URL(string: "https://example.com/manage")!
        ))
        let view = makeViewForDispositionTests(delegate: spy, transaction: transaction)
        // didUpdatePaymentMethodHandler left unset - exercises the SDK's getPaymentSummaryItems() fallback.

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didSelect: PKPaymentMethod())

        XCTAssertEqual(result.paymentSummaryItems.map(\.label), ["Total", "Monthly"])
        XCTAssertEqual(result.paymentSummaryItems.map(\.amount), [
            NSDecimalNumber(string: "10.00"),
            NSDecimalNumber(string: "9.99")
        ])
    }
}

/// PassKit dispatches via `respondsToSelector:`, so this checks the real ObjC selector is wired up.
final class DelegateObjCSelectorRegistrationTests: XCTestCase {
    func testRespondsToDidSelectShippingMethodSelector() {
        let sel = NSSelectorFromString("paymentAuthorizationViewController:didSelectShippingMethod:handler:")
        XCTAssertTrue(EvervaultPaymentView.instancesRespond(to: sel), "EvervaultPaymentView doesn't respond to \(sel) - PassKit will silently treat didSelectShippingMethod as unimplemented.")
    }

    // Known-working control, for comparison.
    func testRespondsToDidChangeCouponCodeSelector() {
        let sel = NSSelectorFromString("paymentAuthorizationViewController:didChangeCouponCode:handler:")
        XCTAssertTrue(EvervaultPaymentView.instancesRespond(to: sel))
    }

    func testRespondsToDidSelectShippingContactSelector() {
        let sel = NSSelectorFromString("paymentAuthorizationViewController:didSelectShippingContact:handler:")
        XCTAssertTrue(EvervaultPaymentView.instancesRespond(to: sel))
    }

    // @required methods can't have this bug - a wrong label fails to compile.
    func testRespondsToDidAuthorizePaymentSelector() {
        let sel = NSSelectorFromString("paymentAuthorizationViewController:didAuthorizePayment:handler:")
        XCTAssertTrue(EvervaultPaymentView.instancesRespond(to: sel))
    }

    func testRespondsToDidSelectPaymentMethodSelector() {
        let sel = NSSelectorFromString("paymentAuthorizationViewController:didSelectPaymentMethod:handler:")
        XCTAssertTrue(EvervaultPaymentView.instancesRespond(to: sel))
    }
}

@MainActor
final class ShippingMethodDelegateTests: XCTestCase {
    func testReturnsDelegateProvidedUpdateWhenImplemented() async {
        let spy = SpyDelegate()
        let view = makeViewForDispositionTests(delegate: spy)
        let expectedUpdate = PKPaymentRequestShippingMethodUpdate(
            paymentSummaryItems: [PKPaymentSummaryItem(label: "Total (shipping method)", amount: NSDecimalNumber(string: "19.99"))]
        )
        spy.didSelectShippingMethodHandler = { _ in expectedUpdate }

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didSelect: PKShippingMethod(label: "Express", amount: NSDecimalNumber(string: "9.99")))

        // Same instance the delegate returned - proves it's a straight passthrough.
        XCTAssertTrue(result === expectedUpdate)
    }

    // Regression coverage: getPaymentSummaryItems() is shared across all PassKit fallback entry
    // points, but CouponCodeDelegateTests only exercises it via didChangeCouponCode. This proves
    // didSelectShippingMethod is wired to the same (fixed) method.
    func testFallsBackToSummaryItemsIncludingRegularBillingForRecurringPayment() async throws {
        let spy = SpyDelegate()
        let transaction = Transaction.recurringPayment(try RecurringPaymentTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            paymentDescription: "Subscription",
            regularBilling: PKRecurringPaymentSummaryItem(label: "Monthly", amount: NSDecimalNumber(string: "9.99")),
            managementURL: URL(string: "https://example.com/manage")!
        ))
        let view = makeViewForDispositionTests(delegate: spy, transaction: transaction)
        // didSelectShippingMethodHandler left unset - exercises the SDK's getPaymentSummaryItems() fallback.

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didSelect: PKShippingMethod(label: "Express", amount: NSDecimalNumber(string: "9.99")))

        XCTAssertEqual(result.paymentSummaryItems.map(\.label), ["Total", "Monthly"])
        XCTAssertEqual(result.paymentSummaryItems.map(\.amount), [
            NSDecimalNumber(string: "10.00"),
            NSDecimalNumber(string: "9.99")
        ])
    }

    // Same rationale as above, covering the other transaction type that appends an item.
    func testFallsBackToSummaryItemsIncludingDisbursementItemForDisbursement() async throws {
        let spy = SpyDelegate()
        let transaction = Transaction.disbursement(try DisbursementTransaction(
            country: "IE",
            currency: "EUR",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount("10.00"))],
            disbursementItem: SummaryItem(label: "Payout", amount: Amount("10.00")),
            requiredRecipientDetails: [],
            merchantCapability: .capability3DS
        ))
        let view = makeViewForDispositionTests(delegate: spy, transaction: transaction)
        // didSelectShippingMethodHandler left unset - exercises the SDK's getPaymentSummaryItems() fallback.

        let result = await view.paymentAuthorizationViewController(makeAuthorizationController(), didSelect: PKShippingMethod(label: "Express", amount: NSDecimalNumber(string: "9.99")))

        XCTAssertEqual(result.paymentSummaryItems.map(\.label), ["Total", "Payout"])
        XCTAssertEqual(result.paymentSummaryItems.map(\.amount), [
            NSDecimalNumber(string: "10.00"),
            NSDecimalNumber(string: "10.00")
        ])
    }
}
