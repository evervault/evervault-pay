import PassKit
import Foundation

public typealias Network = PKPaymentNetwork

public typealias ContactField = PKContactField
public typealias MerchantCapability = PKMerchantCapability

public struct ApplePayNetworkTokenExpiry: Codable, Sendable, Equatable {
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

public struct ApplePayResponse: Codable, Sendable, Equatable {
    public let networkToken: ApplePayNetworkToken
    public let card: ApplePayCard
    public let cryptogram: String
    public let eci: String?
    public let paymentDataType: String
    public let deviceManufacturerIdentifier: String
}

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
    public let country: String
    public let currency: String
    public let paymentSummaryItems: [SummaryItem]

    public let shippingType: PKShippingType
    public let shippingMethods: [PKShippingMethod]
    public let requiredShippingContactFields: Set<ContactField>
    
    public init(country: String, currency: String, paymentSummaryItems: [SummaryItem]) throws {
        self.country = country
        self.currency = currency
        self.paymentSummaryItems = paymentSummaryItems
        self.shippingType = .shipping
        self.shippingMethods = []
        self.requiredShippingContactFields = []

        // Ensure at least one line item is provided
        guard paymentSummaryItems.count > 0 else {
            throw EvervaultError.InvalidTransactionError
        }
    }

    public init(country: String, currency: String, paymentSummaryItems: [SummaryItem], shippingType: PKShippingType, shippingMethods: [PKShippingMethod], requiredShippingContactFields: Set<ContactField>) throws {
        self.country = country
        self.currency = currency
        self.paymentSummaryItems = paymentSummaryItems
        self.shippingType = shippingType
        self.shippingMethods = shippingMethods
        self.requiredShippingContactFields = requiredShippingContactFields

        // Ensure at least one line item is provided
        guard paymentSummaryItems.count > 0 else {
            throw EvervaultError.InvalidTransactionError
        }
    }
    
    @available(iOS 16, *)
    public init(country: Locale.Region, currency: Locale.Currency, paymentSummaryItems: [SummaryItem]) throws {
        self.country = country.identifier
        self.currency = currency.identifier
        self.paymentSummaryItems = paymentSummaryItems
        self.shippingType = .shipping
        self.shippingMethods = []
        self.requiredShippingContactFields = []

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
    public init(country: Locale.Region, currency: Locale.Currency, paymentSummaryItems: [SummaryItem], shippingType: PKShippingType, shippingMethods: [PKShippingMethod], requiredShippingContactFields: Set<ContactField>) throws {
        self.country = country.identifier
        self.currency = currency.identifier
        self.paymentSummaryItems = paymentSummaryItems
        self.shippingType = shippingType
        self.shippingMethods = shippingMethods
        self.requiredShippingContactFields = requiredShippingContactFields

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
    public let country: String
    public let currency: String
    public let paymentSummaryItems: [SummaryItem]
    public let disbursementItem: SummaryItem
    public let instantOutFee: SummaryItem?
    public let requiredRecipientDetails: [ContactField]
    public let merchantCapability: MerchantCapability
    
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
    public let country: String
    public let currency: String
    public let paymentSummaryItems: [SummaryItem]
    public let paymentDescription: String
    public let regularBilling: PKRecurringPaymentSummaryItem
    public let managementURL: URL
    
    public init(country: String, currency: String, paymentSummaryItems: [SummaryItem], paymentDescription: String, regularBilling: PKRecurringPaymentSummaryItem, managementURL: URL) throws {
        self.country = country
        self.currency = currency
        self.paymentSummaryItems = paymentSummaryItems
        self.paymentDescription = paymentDescription
        self.regularBilling = regularBilling
        self.managementURL = managementURL
        
        // 1. Ensure at least one line item is provided
        guard paymentSummaryItems.count > 0 else {
            throw EvervaultError.InvalidTransactionError
        }
    }
    
    @available(iOS 16.0, *)
    public init(country: Locale.Region, currency: Locale.Currency, paymentSummaryItems: [SummaryItem], paymentDescription: String, regularBilling: PKRecurringPaymentSummaryItem, managementURL: URL) throws {
        self.country = country.identifier
        self.currency = currency.identifier
        self.paymentSummaryItems = paymentSummaryItems
        self.paymentDescription = paymentDescription
        self.regularBilling = regularBilling
        self.managementURL = managementURL
        
        // 1. Ensure at least one line item is provided
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
