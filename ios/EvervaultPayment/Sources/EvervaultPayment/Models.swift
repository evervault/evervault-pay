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

/// Prefill input for `PKPaymentRequest.billingContact` / `.shippingContact`.
///
/// Address prefill only appears if `.postalAddress` is in `requiredBillingContactFields` / `requiredShippingContactFields`.
public struct ApplePayPaymentContact: Sendable, Equatable {
    public var givenName: String?
    public var familyName: String?
    public var phoneticGivenName: String?
    public var phoneticFamilyName: String?
    public var emailAddress: String?
    public var phoneNumber: String?
    public var addressLines: [String]?
    public var subLocality: String?
    public var locality: String?
    public var postalCode: String?
    public var subAdministrativeArea: String?
    public var administrativeArea: String?
    public var country: String?
    public var countryCode: String?

    public init(
        givenName: String? = nil,
        familyName: String? = nil,
        phoneticGivenName: String? = nil,
        phoneticFamilyName: String? = nil,
        emailAddress: String? = nil,
        phoneNumber: String? = nil,
        addressLines: [String]? = nil,
        subLocality: String? = nil,
        locality: String? = nil,
        postalCode: String? = nil,
        subAdministrativeArea: String? = nil,
        administrativeArea: String? = nil,
        country: String? = nil,
        countryCode: String? = nil
    ) {
        self.givenName = givenName
        self.familyName = familyName
        self.phoneticGivenName = phoneticGivenName
        self.phoneticFamilyName = phoneticFamilyName
        self.emailAddress = emailAddress
        self.phoneNumber = phoneNumber
        self.addressLines = addressLines
        self.subLocality = subLocality
        self.locality = locality
        self.postalCode = postalCode
        self.subAdministrativeArea = subAdministrativeArea
        self.administrativeArea = administrativeArea
        self.country = country
        self.countryCode = countryCode
    }
}

/// True if at least one of the given values is non-nil.
private func hasAnyValue(_ values: String?...) -> Bool {
    values.contains { $0 != nil }
}

private extension ApplePayPaymentContact {
    /// Returns `nil` unless at least one name field is set, so PassKit never receives an empty name.
    var nameComponents: PersonNameComponents? {
        guard hasAnyValue(givenName, familyName, phoneticGivenName, phoneticFamilyName) else { return nil }

        var components = PersonNameComponents()
        components.givenName = givenName
        components.familyName = familyName

        if hasAnyValue(phoneticGivenName, phoneticFamilyName) {
            var phoneticComponents = PersonNameComponents()
            phoneticComponents.givenName = phoneticGivenName
            phoneticComponents.familyName = phoneticFamilyName
            components.phoneticRepresentation = phoneticComponents
        }

        return components
    }

    /// Returns `nil` unless at least one address field is set, so PassKit never receives an empty address.
    var mutablePostalAddress: CNMutablePostalAddress? {
        let hasAddressLines = addressLines?.isEmpty == false
        guard hasAddressLines || hasAnyValue(subLocality, locality, postalCode, subAdministrativeArea, administrativeArea, country, countryCode) else {
            return nil
        }

        let address = CNMutablePostalAddress()
        address.street = (addressLines ?? []).joined(separator: "\n")
        address.subLocality = subLocality ?? ""
        address.city = locality ?? ""
        address.subAdministrativeArea = subAdministrativeArea ?? ""
        address.state = administrativeArea ?? ""
        address.postalCode = postalCode ?? ""
        address.country = country ?? ""
        address.isoCountryCode = countryCode ?? ""
        return address
    }
}

extension PKContact {
    /// For prefilling the Apple Pay sheet from a plain `ApplePayPaymentContact`.
    convenience init(_ contact: ApplePayPaymentContact) {
        self.init()
        self.name = contact.nameComponents
        self.emailAddress = contact.emailAddress
        self.phoneNumber = contact.phoneNumber.map(CNPhoneNumber.init(stringValue:))
        self.postalAddress = contact.mutablePostalAddress
    }
}

public enum ApplePayTransactionType: String, Codable, Sendable, Equatable {
    case oneOff
    case recurring
    case disbursement
    case automaticReload

    init(_ transaction: Transaction) throws {
        switch transaction {
        case .oneOffPayment:
            self = .oneOff
        case .recurringPayment:
            self = .recurring
        case .disbursement:
            self = .disbursement
        default:
            if #available(iOS 16.0, *), case .automaticReload = transaction {
                self = .automaticReload
            } else {
                throw EvervaultError.UnsupportedVersionError
            }
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
/// A rejection is reported via `didDeclinePayment`/`onDecline`, wrapping the reason you provide - it never
/// reaches `onResult`, which only reports genuine SDK-level outcomes.
/// Use your own `Error`-conforming type here if you want exhaustive `switch` handling downstream.
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
    public var supportsCouponCode: Bool
    public var couponCode: String?
    public var billingContact: ApplePayPaymentContact?
    public var shippingContact: ApplePayPaymentContact?

    public init(country: String, currency: String, paymentSummaryItems: [SummaryItem], shippingType: PKShippingType = .shipping, shippingMethods: [PKShippingMethod] = [], requiredShippingContactFields: Set<ContactField> = [], requestPayerDetails: Set<ContactField> = [], supportsCouponCode: Bool = false, couponCode: String? = nil, billingContact: ApplePayPaymentContact? = nil, shippingContact: ApplePayPaymentContact? = nil) throws {
        self.country = country
        self.currency = currency
        self.paymentSummaryItems = paymentSummaryItems
        self.shippingType = shippingType
        self.shippingMethods = shippingMethods
        self.requiredShippingContactFields = requiredShippingContactFields
        self.requestPayerDetails = requestPayerDetails
        self.supportsCouponCode = supportsCouponCode
        self.couponCode = couponCode
        self.billingContact = billingContact
        self.shippingContact = shippingContact

        guard paymentSummaryItems.count > 0 else {
            throw EvervaultError.InvalidTransactionError
        }
    }

    @available(iOS 16, *)
    public init(country: Locale.Region, currency: Locale.Currency, paymentSummaryItems: [SummaryItem], shippingType: PKShippingType = .shipping, shippingMethods: [PKShippingMethod] = [], requiredShippingContactFields: Set<ContactField> = [], requestPayerDetails: Set<ContactField> = [], supportsCouponCode: Bool = false, couponCode: String? = nil, billingContact: ApplePayPaymentContact? = nil, shippingContact: ApplePayPaymentContact? = nil) throws {
        self.country = country.identifier
        self.currency = currency.identifier
        self.paymentSummaryItems = paymentSummaryItems
        self.shippingType = shippingType
        self.shippingMethods = shippingMethods
        self.requiredShippingContactFields = requiredShippingContactFields
        self.requestPayerDetails = requestPayerDetails
        self.supportsCouponCode = supportsCouponCode
        self.couponCode = couponCode
        self.billingContact = billingContact
        self.shippingContact = shippingContact

        guard paymentSummaryItems.count > 0 else {
            throw EvervaultError.InvalidTransactionError
        }
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
        
        guard paymentSummaryItems.count > 0 else {
            throw EvervaultError.InvalidTransactionError
        }
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
    public var supportsCouponCode: Bool
    public var couponCode: String?
    public var shippingType: PKShippingType
    public var requiredShippingContactFields: Set<ContactField>
    public var billingContact: ApplePayPaymentContact?
    public var shippingContact: ApplePayPaymentContact?

    public init(country: String, currency: String, paymentSummaryItems: [SummaryItem] = [], paymentDescription: String, regularBilling: PKRecurringPaymentSummaryItem, managementURL: URL, requestPayerDetails: Set<ContactField> = [], supportsCouponCode: Bool = false, couponCode: String? = nil, billingContact: ApplePayPaymentContact? = nil, shippingType: PKShippingType = .shipping, requiredShippingContactFields: Set<ContactField> = [], shippingContact: ApplePayPaymentContact? = nil) throws {
        self.country = country
        self.currency = currency
        self.paymentSummaryItems = paymentSummaryItems
        self.paymentDescription = paymentDescription
        self.regularBilling = regularBilling
        self.managementURL = managementURL
        self.requestPayerDetails = requestPayerDetails
        self.supportsCouponCode = supportsCouponCode
        self.couponCode = couponCode
        self.shippingType = shippingType
        self.requiredShippingContactFields = requiredShippingContactFields
        self.billingContact = billingContact
        self.shippingContact = shippingContact
    }

    @available(iOS 16.0, *)
    public init(country: Locale.Region, currency: Locale.Currency, paymentSummaryItems: [SummaryItem] = [], paymentDescription: String, regularBilling: PKRecurringPaymentSummaryItem, managementURL: URL, requestPayerDetails: Set<ContactField> = [], supportsCouponCode: Bool = false, couponCode: String? = nil, billingContact: ApplePayPaymentContact? = nil, shippingType: PKShippingType = .shipping, requiredShippingContactFields: Set<ContactField> = [], shippingContact: ApplePayPaymentContact? = nil) throws {
        self.country = country.identifier
        self.currency = currency.identifier
        self.paymentSummaryItems = paymentSummaryItems
        self.paymentDescription = paymentDescription
        self.regularBilling = regularBilling
        self.managementURL = managementURL
        self.requestPayerDetails = requestPayerDetails
        self.supportsCouponCode = supportsCouponCode
        self.couponCode = couponCode
        self.shippingType = shippingType
        self.requiredShippingContactFields = requiredShippingContactFields
        self.billingContact = billingContact
        self.shippingContact = shippingContact

        guard currency.isISOCurrency else {
            throw EvervaultError.InvalidCurrencyError
        }
        guard country.isISORegion else {
            throw EvervaultError.InvalidCountryError
        }
    }
}

public struct AutomaticReloadPaymentTransaction {
    public var country: String
    public var currency: String
    public var paymentSummaryItems: [SummaryItem]
    public var paymentDescription: String
    public var automaticReloadBilling: SummaryItem
    public var automaticReloadThresholdAmount: Amount?
    public var managementURL: URL
    public var billingAgreement: String?
    public var requestPayerDetails: Set<ContactField>
    public var supportsCouponCode: Bool
    public var couponCode: String?
    public var shippingType: PKShippingType
    public var requiredShippingContactFields: Set<ContactField>
    public var billingContact: ApplePayPaymentContact?
    public var shippingContact: ApplePayPaymentContact?

    public init(country: String, currency: String, paymentSummaryItems: [SummaryItem] = [], paymentDescription: String, automaticReloadBilling: SummaryItem, automaticReloadThresholdAmount: Amount? = nil, managementURL: URL, requestPayerDetails: Set<ContactField> = [], supportsCouponCode: Bool = false, couponCode: String? = nil, billingContact: ApplePayPaymentContact? = nil, shippingType: PKShippingType = .shipping, requiredShippingContactFields: Set<ContactField> = [], shippingContact: ApplePayPaymentContact? = nil) throws {
        self.country = country
        self.currency = currency
        self.paymentSummaryItems = paymentSummaryItems
        self.paymentDescription = paymentDescription
        self.automaticReloadBilling = automaticReloadBilling
        self.automaticReloadThresholdAmount = automaticReloadThresholdAmount
        self.managementURL = managementURL
        self.requestPayerDetails = requestPayerDetails
        self.supportsCouponCode = supportsCouponCode
        self.couponCode = couponCode
        self.shippingType = shippingType
        self.requiredShippingContactFields = requiredShippingContactFields
        self.billingContact = billingContact
        self.shippingContact = shippingContact
    }

    @available(iOS 16.0, *)
    public init(country: Locale.Region, currency: Locale.Currency, paymentSummaryItems: [SummaryItem] = [], paymentDescription: String, automaticReloadBilling: SummaryItem, automaticReloadThresholdAmount: Amount? = nil, managementURL: URL, requestPayerDetails: Set<ContactField> = [], supportsCouponCode: Bool = false, couponCode: String? = nil, billingContact: ApplePayPaymentContact? = nil, shippingType: PKShippingType = .shipping, requiredShippingContactFields: Set<ContactField> = [], shippingContact: ApplePayPaymentContact? = nil) throws {
        self.country = country.identifier
        self.currency = currency.identifier
        self.paymentSummaryItems = paymentSummaryItems
        self.paymentDescription = paymentDescription
        self.automaticReloadBilling = automaticReloadBilling
        self.automaticReloadThresholdAmount = automaticReloadThresholdAmount
        self.managementURL = managementURL
        self.requestPayerDetails = requestPayerDetails
        self.supportsCouponCode = supportsCouponCode
        self.couponCode = couponCode
        self.shippingType = shippingType
        self.requiredShippingContactFields = requiredShippingContactFields
        self.billingContact = billingContact
        self.shippingContact = shippingContact

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
    // Not @available-gated: Swift disallows @available on enum cases with an associated
    // value, and AutomaticReloadPaymentTransaction itself is safe to construct pre-iOS 16
    // (see the note on that struct). The genuine iOS 16+ requirement is enforced at the
    // point we actually build/present the PassKit request, not at the point of identifying
    // which transaction kind this is.
    case automaticReload(AutomaticReloadPaymentTransaction)
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
