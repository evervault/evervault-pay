import PassKit
import Foundation
import Contacts

public typealias Network = PKPaymentNetwork

public typealias ContactField = PKContactField
public typealias MerchantCapability = PKMerchantCapability
public typealias ShippingMethod = PKShippingMethod
public typealias ShippingContact = PKContact
public typealias ShippingContactField = PKContactField
public typealias ShippingType = PKShippingType

public struct ApplePayNetworkTokenExpiry: Codable, Sendable, Equatable {
    init(month: String, year: String) {
        self.month = month
        self.year = year
    }

    init(month: Int, year: Int) {
        self.month = month.formatted()
        self.year = year.formatted()
    }

    public let month: String
    public let year: String
}

public struct ApplePayNetworkToken: Codable, Sendable, Equatable {
    public let number: String
    public let expiry: ApplePayNetworkTokenExpiry
    public let rawExpiry: String
    public let tokenServiceProvider: String
}

public struct ApplePayCard: Codable, Sendable, Equatable {
    public let brand: String?
    public let funding: String?
    public let segment: String?
    public let country: String?
    public let currency: String?
    public let issuer: String?
}

private func nilIfEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
}

public struct ApplePayPostalAddress: Codable, Sendable, Equatable {
    public let street: String?
    public let city: String?
    public let state: String?
    public let postalCode: String?
    public let country: String?
    public let isoCountryCode: String?

    init(_ address: CNPostalAddress) {
        self.street = nilIfEmpty(address.street)
        self.city = nilIfEmpty(address.city)
        self.state = nilIfEmpty(address.state)
        self.postalCode = nilIfEmpty(address.postalCode)
        self.country = nilIfEmpty(address.country)
        self.isoCountryCode = nilIfEmpty(address.isoCountryCode)
    }
}

public struct ApplePayContact: Codable, Sendable, Equatable {
    public let givenName: String?
    public let familyName: String?
    public let phoneticGivenName: String?
    public let phoneticFamilyName: String?
    public let emailAddress: String?
    public let phoneNumber: String?
    public let postalAddress: ApplePayPostalAddress?

    init?(_ contact: PKContact?) {
        guard let contact else { return nil }
        self.givenName = nilIfEmpty(contact.name?.givenName)
        self.familyName = nilIfEmpty(contact.name?.familyName)
        self.phoneticGivenName = nilIfEmpty(contact.name?.phoneticRepresentation?.givenName)
        self.phoneticFamilyName = nilIfEmpty(contact.name?.phoneticRepresentation?.familyName)
        self.emailAddress = nilIfEmpty(contact.emailAddress)
        self.phoneNumber = nilIfEmpty(contact.phoneNumber?.stringValue)
        self.postalAddress = contact.postalAddress.map(ApplePayPostalAddress.init)
    }
}

public enum ApplePayTransactionType: String, Codable, Sendable, Equatable {
    case oneOff
    case recurring
    case disbursement

    init(_ transaction: Transaction) {
        switch transaction {
        case .oneOffPayment:
            self = .oneOff
        case .recurringPayment:
            self = .recurring
        case .disbursement:
            self = .disbursement
        }
    }
}

public struct ApplePayResponse: Codable, Sendable, Equatable {
    public let networkToken: ApplePayNetworkToken
    public let card: ApplePayCard
    public let cryptogram: String
    public let eci: String?
    public let paymentDataType: String
    public let deviceManufacturerIdentifier: String
    public let transactionId: String?
    public let billingContact: ApplePayContact?
    public let shippingContact: ApplePayContact?
    public let transactionType: ApplePayTransactionType?

    init(networkToken: ApplePayNetworkToken, card: ApplePayCard, cryptogram: String, eci: String?, paymentDataType: String, deviceManufacturerIdentifier: String, transactionId: String? = nil, billingContact: ApplePayContact? = nil, shippingContact: ApplePayContact? = nil, transactionType: ApplePayTransactionType? = nil) {
        self.networkToken = networkToken
        self.card = card
        self.cryptogram = cryptogram
        self.eci = eci
        self.paymentDataType = paymentDataType
        self.deviceManufacturerIdentifier = deviceManufacturerIdentifier
        self.transactionId = transactionId
        self.billingContact = billingContact
        self.shippingContact = shippingContact
        self.transactionType = transactionType
    }

    func enriched(billingContact: ApplePayContact?, shippingContact: ApplePayContact?, transactionType: ApplePayTransactionType) -> ApplePayResponse {
        ApplePayResponse(
            networkToken: networkToken,
            card: card,
            cryptogram: cryptogram,
            eci: eci,
            paymentDataType: paymentDataType,
            deviceManufacturerIdentifier: deviceManufacturerIdentifier,
            transactionId: transactionId,
            billingContact: billingContact,
            shippingContact: shippingContact,
            transactionType: transactionType
        )
    }
}

/// The merchant's decision on whether to approve the payment, returned from the `shouldAuthorize` hook.
/// The SDK reports a rejection as `EvervaultError.MerchantDeclinedError`, wrapping the reason you provide.
/// Use your own `Error`-conforming type here if you want exhaustive `switch` handling downstream in `onResult`.
public typealias AuthorizationDisposition = Result<(), Error>

/// Amount wrapper around NSDecimalNumber
/// Allows us to accept ints, floats, etc. in the future if we want
public struct Amount {
    public let amount: NSDecimalNumber
    
    public init(_ amount: String) {
        self.amount = NSDecimalNumber(string: amount)
    }
}

/// Summary item for display in the Apple Pay sheet
public struct SummaryItem {
    public let label: String
    public let amount: Amount
    
    public init(label: String, amount: Amount) {
        self.label = label
        self.amount = amount
    }
}

public struct OneOffPaymentTransaction {
    public var country: String
    public var currency: String
    public var paymentSummaryItems: [SummaryItem]

    public var shippingType: PKShippingType
    public var shippingMethods: [PKShippingMethod]
    public var requiredShippingContactFields: Set<ContactField>
    public var requestPayerDetails: Set<ContactField>

    public init(country: String, currency: String, paymentSummaryItems: [SummaryItem], requestPayerDetails: Set<ContactField> = []) throws {
        self.country = country
        self.currency = currency
        self.paymentSummaryItems = paymentSummaryItems
        self.shippingType = .shipping
        self.shippingMethods = []
        self.requiredShippingContactFields = []
        self.requestPayerDetails = requestPayerDetails

        // Ensure at least one line item is provided
        guard paymentSummaryItems.count > 0 else {
            throw EvervaultError.InvalidTransactionError
        }
    }

    public init(country: String, currency: String, paymentSummaryItems: [SummaryItem], shippingType: PKShippingType, shippingMethods: [PKShippingMethod], requiredShippingContactFields: Set<ContactField>, requestPayerDetails: Set<ContactField> = []) throws {
        self.country = country
        self.currency = currency
        self.paymentSummaryItems = paymentSummaryItems
        self.shippingType = shippingType
        self.shippingMethods = shippingMethods
        self.requiredShippingContactFields = requiredShippingContactFields
        self.requestPayerDetails = requestPayerDetails

        // Ensure at least one line item is provided
        guard paymentSummaryItems.count > 0 else {
            throw EvervaultError.InvalidTransactionError
        }
    }

    @available(iOS 16, *)
    public init(country: Locale.Region, currency: Locale.Currency, paymentSummaryItems: [SummaryItem], requestPayerDetails: Set<ContactField> = []) throws {
        self.country = country.identifier
        self.currency = currency.identifier
        self.paymentSummaryItems = paymentSummaryItems
        self.shippingType = .shipping
        self.shippingMethods = []
        self.requiredShippingContactFields = []
        self.requestPayerDetails = requestPayerDetails

        // Ensure at least one line item is provided
        guard paymentSummaryItems.count > 0 else {
            throw EvervaultError.InvalidTransactionError
        }

        // Ensure valid currency
        guard currency.isISOCurrency else {
            throw EvervaultError.InvalidCurrencyError
        }

        guard country.isISORegion else {
            throw EvervaultError.InvalidCountryError
        }
    }

    @available(iOS 16, *)
    public init(country: Locale.Region, currency: Locale.Currency, paymentSummaryItems: [SummaryItem], shippingType: PKShippingType, shippingMethods: [PKShippingMethod], requiredShippingContactFields: Set<ContactField>, requestPayerDetails: Set<ContactField> = []) throws {
        self.country = country.identifier
        self.currency = currency.identifier
        self.paymentSummaryItems = paymentSummaryItems
        self.shippingType = shippingType
        self.shippingMethods = shippingMethods
        self.requiredShippingContactFields = requiredShippingContactFields
        self.requestPayerDetails = requestPayerDetails

        // Ensure at least one line item is provided
        guard paymentSummaryItems.count > 0 else {
            throw EvervaultError.InvalidTransactionError
        }

        // Ensure valid currency
        guard currency.isISOCurrency else {
            throw EvervaultError.InvalidCurrencyError
        }

        guard country.isISORegion else {
            throw EvervaultError.InvalidCountryError
        }
    }
}

public struct DisbursementTransaction {
    public var country: String
    public var currency: String
    public var paymentSummaryItems: [SummaryItem]
    public var disbursementItem: SummaryItem
    public var instantOutFee: SummaryItem?
    public var requiredRecipientDetails: [ContactField]
    public var merchantCapability: MerchantCapability

    public init(country: String, currency: String, paymentSummaryItems: [SummaryItem], disbursementItem: SummaryItem, instantOutFee: SummaryItem? = nil, requiredRecipientDetails: [ContactField], merchantCapability: MerchantCapability) throws {
        self.country = country
        self.currency = currency
        self.paymentSummaryItems = paymentSummaryItems
        self.disbursementItem = disbursementItem
        self.instantOutFee = instantOutFee
        self.requiredRecipientDetails = requiredRecipientDetails
        self.merchantCapability = merchantCapability
        
        // 1. Ensure at least one line item is provided
        guard paymentSummaryItems.count > 0 else {
            throw EvervaultError.InvalidTransactionError
        }
    }
    
    @available(iOS 16, *)
    public init(country: Locale.Region, currency: Locale.Currency, paymentSummaryItems: [SummaryItem], disbursementItem: SummaryItem, instantOutFee: SummaryItem? = nil, requiredRecipientDetails: [ContactField], merchantCapability: MerchantCapability) throws {
        self.country = country.identifier
        self.currency = currency.identifier
        self.paymentSummaryItems = paymentSummaryItems
        self.disbursementItem = disbursementItem
        self.instantOutFee = instantOutFee
        self.requiredRecipientDetails = requiredRecipientDetails
        self.merchantCapability = merchantCapability
        
        // Ensure at least one line item is provided
        guard paymentSummaryItems.count > 0 else {
            throw EvervaultError.InvalidTransactionError
        }
        
        // Ensure valid currency
        guard currency.isISOCurrency else {
            throw EvervaultError.InvalidCurrencyError
        }

        guard country.isISORegion else {
            throw EvervaultError.InvalidCountryError
        }
    }
}

public struct RecurringPaymentTransaction {
    public var country: String
    public var currency: String
    public var paymentSummaryItems: [SummaryItem]
    public var paymentDescription: String
    public var regularBilling: PKRecurringPaymentSummaryItem
    public var managementURL: URL
    public var trialBilling: PKRecurringPaymentSummaryItem?
    public var billingAgreement: String?
    public var requestPayerDetails: Set<ContactField>

    public init(country: String, currency: String, paymentSummaryItems: [SummaryItem] = [], paymentDescription: String, regularBilling: PKRecurringPaymentSummaryItem, managementURL: URL, requestPayerDetails: Set<ContactField> = []) throws {
        self.country = country
        self.currency = currency
        self.paymentSummaryItems = paymentSummaryItems
        self.paymentDescription = paymentDescription
        self.regularBilling = regularBilling
        self.managementURL = managementURL
        self.requestPayerDetails = requestPayerDetails
    }

    @available(iOS 16.0, *)
    public init(country: Locale.Region, currency: Locale.Currency, paymentSummaryItems: [SummaryItem] = [], paymentDescription: String, regularBilling: PKRecurringPaymentSummaryItem, managementURL: URL, requestPayerDetails: Set<ContactField> = []) throws {
        self.country = country.identifier
        self.currency = currency.identifier
        self.paymentSummaryItems = paymentSummaryItems
        self.paymentDescription = paymentDescription
        self.regularBilling = regularBilling
        self.managementURL = managementURL
        self.requestPayerDetails = requestPayerDetails

        // Ensure valid currency
        guard currency.isISOCurrency else {
            throw EvervaultError.InvalidCurrencyError
        }

        guard country.isISORegion else {
            throw EvervaultError.InvalidCountryError
        }
    }
}

public enum Transaction {
    case oneOffPayment(OneOffPaymentTransaction)
    case disbursement(DisbursementTransaction)
    case recurringPayment(RecurringPaymentTransaction)
}

struct ApplePayTokenHeader: Codable {
    let publicKeyHash: String
    let ephemeralPublicKey: String
    let transactionId: String
}

struct ApplePayToken: Codable {
    let data: String
    let signature: String
    let header: ApplePayTokenHeader
    let version: String
}

struct ApplePayPayload: Codable {
  let isNative: Bool
  let encryptedCredentials: ApplePayToken
}
