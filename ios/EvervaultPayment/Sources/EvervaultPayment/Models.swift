import PassKit
import Foundation

public typealias Network = PKPaymentNetwork

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

public enum TransactionType {
    case oneOffPayment
    case disbursement
}

/// Transaction details, including country, currency, and summary items
public struct Transaction {
    public let type: TransactionType
    public let country: String
    public let currency: String
    public let paymentSummaryItems: [SummaryItem]
    public let requiredRecipientDetails: [PKContactField]
    
    internal init(type: TransactionType, country: String, currency: String, paymentSummaryItems: [SummaryItem], requiredRecipientDetails: [PKContactField]) throws {
        self.type = type
        self.country = country
        self.currency = currency
        
        // 1. Ensure at least one line item is provided
        guard paymentSummaryItems.count > 0 else {
            throw EvervaultError.InvalidTransactionError
        }
        
        // Ensure valid currency
        if #available(iOS 16, *) {
            guard Locale.Currency(currency).isISOCurrency else {
                throw EvervaultError.InvalidCurrencyError
            }

            guard Locale.Region(country).isISORegion else {
                throw EvervaultError.InvalidCountryError
            }
        }
        
        self.paymentSummaryItems = paymentSummaryItems
        self.requiredRecipientDetails = requiredRecipientDetails
    }

    public static func create(type: TransactionType, country: String, currency: String, paymentSummaryItems: [SummaryItem]) throws -> Transaction {
        return try Transaction(type: type, country: country, currency: currency, paymentSummaryItems: paymentSummaryItems, requiredRecipientDetails: [])
    }
    
    @available(iOS 16, *)
    public static func create(type: TransactionType, country: Locale.Region, currency: Locale.Currency, paymentSummaryItems: [SummaryItem]) throws -> Transaction {
        return try Transaction(type: type, country: country.identifier, currency: currency.identifier, paymentSummaryItems: paymentSummaryItems, requiredRecipientDetails: [])
    }
    
    public static func createOneOff(country: String, currency: String, paymentSummaryItems: [SummaryItem]) throws -> Transaction {
        return try Transaction(type: .oneOffPayment, country: country, currency: currency, paymentSummaryItems: paymentSummaryItems, requiredRecipientDetails: [])
    }
    
    @available(iOS 16, *)
    public static func createOneOff(country: Locale.Region, currency: Locale.Currency, paymentSummaryItems: [SummaryItem]) throws -> Transaction {
        return try Transaction(type: .oneOffPayment, country: country.identifier, currency: currency.identifier, paymentSummaryItems: paymentSummaryItems, requiredRecipientDetails: [])
    }
    
    @available(iOS 17.0, *)
    public static func createDisbursement(country: String, currency: String, paymentSummaryItems: [SummaryItem], requiredRecipientDetails: [PKContactField]) throws -> Transaction {
        return try Transaction(type: .disbursement, country: country, currency: currency, paymentSummaryItems: paymentSummaryItems, requiredRecipientDetails: requiredRecipientDetails)
    }
    
    @available(iOS 17.0, *)
    public static func createDisbursement(country: Locale.Region, currency: Locale.Currency, paymentSummaryItems: [SummaryItem], requiredRecipientDetails: [PKContactField]) throws -> Transaction {
        return try Transaction(type: .disbursement, country: country.identifier, currency: currency.identifier, paymentSummaryItems: paymentSummaryItems, requiredRecipientDetails: requiredRecipientDetails)
    }
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
