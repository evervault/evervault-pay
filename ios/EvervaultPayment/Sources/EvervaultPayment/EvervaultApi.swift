import PassKit

/// Simple async API wrapper to send the Apple Pay token to the Evervault backend for decryption and re-encryption with Evervault Encryption.
struct EvervaultApi {
    static func sendPaymentToken(_ appUuid: String, _ payment: PKPayment) async throws -> ApplePayResponse? {
        guard let url = URL(string: "https://api.evervault.io/frontend/apple-pay/credentials") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appUuid, forHTTPHeaderField: "x-evervault-app-id")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let requestBody = ApplePayPayload(isNative: true, paymentData: payment.token.paymentData)
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check for HTTP 2xx
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        // TODO: Decode JSON response
        var applePayResponse: ApplePayResponse?
        let decoder = JSONDecoder()
        do {
            // Decode into our model
            // TODO: remove - testing
            applePayResponse = ApplePayResponse()
            // TODO: uncomment
            // applePayResponse = try decoder.decode(ApplePayResponse.self, from: data)
            // TODO: remove
            print("Apple Pay Response:", applePayResponse!)
            return applePayResponse
        } catch {
            // TODO: remove
            print("Failed to decode JSON:", error)
            throw EvervaultError.DecodingError(underlying: error)
        }
    }
}
