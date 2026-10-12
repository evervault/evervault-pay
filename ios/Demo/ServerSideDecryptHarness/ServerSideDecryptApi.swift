//
//  ServerSideDecryptApi.swift
//  ServerSideDecryptHarness
//
//  Test harness for server-side Apple Pay decryption.
//  Sends the Apple Pay token straight to `POST /payments/apple-pay/decrypt` with an API key,
//  like a merchant's own server would after getting the token without our SDK
//  (e.g. through Apple Messages for Business). Doesn't use the SDK's `EvervaultApi` on purpose.
//

import Foundation
import PassKit

/// Reads the harness config from the scheme's environment variables, so the API key never gets committed.
/// Xcode only passes these when it launches the app, so always run it from Xcode.
struct ServerSideDecryptConfig {
    static let baseUrlKey = "SERVER_SIDE_DECRYPT_BASE_URL"
    static let apiKeyKey = "SERVER_SIDE_DECRYPT_API_KEY"
    static let merchantIdKey = "SERVER_SIDE_DECRYPT_MERCHANT_ID"

    private static let defaultBaseUrl = "https://api.evervault.com"

    let baseUrl: String
    let apiKey: String
    let merchantId: String

    /// Returns the config, or the names of the variables still missing from the scheme.
    static func load(from environment: [String: String] = ProcessInfo.processInfo.environment) -> Result<ServerSideDecryptConfig, MissingConfig> {
        let baseUrl = nonEmpty(environment[baseUrlKey]) ?? defaultBaseUrl
        let apiKey = nonEmpty(environment[apiKeyKey])
        let merchantId = nonEmpty(environment[merchantIdKey])

        guard let apiKey, let merchantId else {
            let missing = [(apiKeyKey, apiKey), (merchantIdKey, merchantId)]
                .filter { $0.1 == nil }
                .map { $0.0 }
            return .failure(MissingConfig(variables: missing))
        }
        return .success(ServerSideDecryptConfig(baseUrl: baseUrl, apiKey: apiKey, merchantId: merchantId))
    }

    struct MissingConfig: Error {
        let variables: [String]
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

/// Mirrors Apple's `PKPaymentToken.paymentData` JSON shape.
struct ServerSideApplePayToken: Codable {
    struct Header: Codable {
        let ephemeralPublicKey: String
        let publicKeyHash: String
        let transactionId: String
    }

    let data: String
    let signature: String
    let header: Header
    let version: String
}

private struct DecryptRequestBody: Encodable {
    let paymentData: ServerSideApplePayToken
}

enum ServerSideDecryptError: LocalizedError {
    case invalidBaseUrl(String)
    case undecodableToken(underlying: Error)
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case let .invalidBaseUrl(url):
            return "Invalid base URL: \(url)"
        case let .undecodableToken(underlying):
            return "Couldn't decode PKPaymentToken.paymentData (are you on a physical device?): \(underlying.localizedDescription)"
        case let .httpError(status, body):
            return "HTTP \(status)\n\n\(body)"
        }
    }
}

struct ServerSideDecryptApi {
    let config: ServerSideDecryptConfig

    /// Sends the token to the decrypt endpoint and returns the response as formatted JSON.
    func decrypt(_ token: PKPaymentToken) async throws -> String {
        guard let url = URL(string: "\(config.baseUrl)/payments/apple-pay/decrypt") else {
            throw ServerSideDecryptError.invalidBaseUrl(config.baseUrl)
        }

        let paymentData: ServerSideApplePayToken
        do {
            paymentData = try JSONDecoder().decode(ServerSideApplePayToken.self, from: token.paymentData)
        } catch {
            throw ServerSideDecryptError.undecodableToken(underlying: error)
        }

        var request = URLRequest(url: url)
        // Apple Pay gives us about 30 seconds to report a result before the sheet gives up,
        // so fail a bit earlier than that instead of using the default 60 second timeout.
        request.timeoutInterval = 25
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        // No x-evervault-app-id header needed: the backend works out the app from the API key.
        request.setValue(config.apiKey, forHTTPHeaderField: "api-key")
        request.httpBody = try JSONEncoder().encode(DecryptRequestBody(paymentData: paymentData))

        let (data, response) = try await URLSession.shared.data(for: request)
        let body = prettyPrinted(data)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw ServerSideDecryptError.httpError(status: http.statusCode, body: body)
        }
        return body
    }

    private func prettyPrinted(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8)
        else {
            return String(data: data, encoding: .utf8) ?? "<\(data.count) bytes, not UTF-8>"
        }
        return string
    }
}
