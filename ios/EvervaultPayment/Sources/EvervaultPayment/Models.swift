import PassKit
import Foundation

public typealias Network = PKPaymentNetwork

public struct ApplePayNetworkTokenExpiry: Codable, Sendable {
    public let month: String
    public let year: String
    
    public init() {
        self.month = "02"
        self.year = "26"
    }
}

public struct ApplePayNetworkToken: Codable, Sendable {
    public let number: String
    public let expiry: ApplePayNetworkTokenExpiry
    public let rawExpiry: String
    public let tokenServiceProvider: String
    
    public init() {
        let uuid = NSUUID().uuidString
        let encoded = uuid.data(using: .utf8)?.base64EncodedString()
        self.number = "ev:\(encoded ?? "encodedStringFailedToEncode"):$"
        self.expiry = ApplePayNetworkTokenExpiry()
        self.rawExpiry = "rawExpiryValue"
        self.tokenServiceProvider = "tokenServiceProviderValue"
    }
}

public struct ApplePayCard: Codable, Sendable {
    public let brand: String?
    public let funding: String?
    public let segment: String?
    public let country: String?
    public let currency: String?
    public let issuer: String?

    // TODO: remove
    public init() {
        self.brand = nil
        self.funding = nil
        self.segment = nil
        self.country = nil
        self.currency = nil
        self.issuer = nil
    }
}

public struct ApplePayResponse: Codable, Sendable  {
    public let networkToken: ApplePayNetworkToken
    public let card: ApplePayCard
    public let cryptogram: String
    public let eci: String?
    public let paymentDataType: String
    public let deviceManufacturerIdentifier: String
    
    // TODO: remove
    public init() {
        let uuid = NSUUID().uuidString
        let encoded = uuid.data(using: .utf8)?.base64EncodedString()
        
        self.networkToken = ApplePayNetworkToken()
        self.card = ApplePayCard()
        self.cryptogram = encoded!
        self.eci = "eciValue"
        self.paymentDataType = "paymentDataTypeValue"
        self.deviceManufacturerIdentifier = "deviceManufacturerIdentifierValue"
    }
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

/// Transaction details, including country, currency, and summary items
public struct Transaction {
    public let country: String
    public let currency: String
    public let paymentSummaryItems: [SummaryItem]

    public init(country: String, currency: String, paymentSummaryItems: [SummaryItem]) throws {
        self.country = country
        self.currency = currency
        
        // 1. Ensure at least one line item is provided
        guard paymentSummaryItems.count > 0 else {
            throw EvervaultError.InvalidTransactionError
        }
        self.paymentSummaryItems = paymentSummaryItems
    }
}

struct ApplePayPayload: Codable {
  let isNative: Bool
  let paymentData: Data
}
