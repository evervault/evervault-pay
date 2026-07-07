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
            deviceManufacturerIdentifier: "device-id"
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
