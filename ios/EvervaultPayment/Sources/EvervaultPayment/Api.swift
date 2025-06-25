import PassKit

struct PaymentRequest: Codable {
    public let encryptedCredentials: PaymentData;
    public let isNative: Bool;
    
    init(encryptedCredentials: PaymentData, isNative: Bool) {
        self.encryptedCredentials = encryptedCredentials
        self.isNative = isNative
    }
}

/// Simple async API wrapper to send the Apple Pay token to the Evervault backend for decryption and re-encryption with Evervault Encryption.
struct EvervaultApi {
    static func sendPaymentToken(_ appUuid: String, _ token: PaymentData) async throws -> ApplePayResponse? {
        let paymentRequest = PaymentRequest(encryptedCredentials: token, isNative: true)
        
        
        
        guard let url = URL(string: "https://api.evervault.io/frontend/apple-pay/credentials") else { return nil }
        var request = URLRequest(url: url)
        request.httpBody = try JSONEncoder().encode(paymentRequest)
        request.addValue("app_c7c594325ed9", forHTTPHeaderField: "x-evervault-app-id")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        let (data, response) = try await URLSession.shared.data(for: request)
        let string = String(bytes: data, encoding: .utf8)
        print(string ?? "nil")
        // Check for HTTP 2xx
        print(response)
        print(data)
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
            // applePayResponse = ApplePayResponse()
            // TODO: uncomment
             applePayResponse = try decoder.decode(ApplePayResponse.self, from: data)
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
