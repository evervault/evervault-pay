import PassKit

/// Simple async API wrapper to send the Apple Pay token to the Evervault backend for decryption and re-encryption with Evervault Encryption.
struct EvervaultApi {
    private static let defaultBaseUrl = "https://api.evervault.com"

    static func sendPaymentToken(_ appUuid: String, _ payment: PKPayment) async throws -> ApplePayResponse? {
        let evervaultBaseURL = ProcessInfo.processInfo.environment["EVERVAULT_BASE_URL"] ?? EvervaultApi.defaultBaseUrl
        guard let url = URL(string: "\(evervaultBaseURL)/frontend/apple-pay/credentials") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appUuid, forHTTPHeaderField: "x-evervault-app-id")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
    
        do {
            let decoded = try JSONDecoder().decode(ApplePayToken.self, from: payment.token.paymentData)
            let requestBody = ApplePayPayload(isNative: true, encryptedCredentials: decoded)
            let encodedBody = try JSONEncoder().encode(requestBody)
            
            request.httpBody = encodedBody
            
            let (data, response) = try await URLSession.shared.data(for: request)
            let bodyString = String(data: data, encoding: .utf8)
            
            // Check for HTTP 2xx
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode)
            else {
                throw URLError(.badServerResponse)
            }
            
            let applePayResponse = try JSONDecoder().decode(ApplePayResponse.self, from: data)
            return applePayResponse
        } catch {
            throw EvervaultError.InternalError(underlying: error)
        }
    }
}
