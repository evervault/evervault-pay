import PassKit

/// Simple async API wrapper to send the Apple Pay token to the Evervault backend for decryption and re-encryption with Evervault Encryption.
struct EvervaultApi {
    
    // MARK: – Async/Await version (iOS 13+)
    #if compiler(>=5.5) && canImport(_Concurrency)
    @available(iOS 13.0, *)
    static func sendPaymentToken(_ appUuid: String, _ payment: PKPayment) async throws -> ApplePayResponse? {
        
        let url = Bundle.main.evervaultBaseURL.appendingPathComponent("/frontend/apple-pay/credentials")
        
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
            throw EvervaultError.DecodingError(underlying: error)
        }
    }
    #endif
    
    // MARK: – Completion‐handler version (iOS 12+)
    public static func sendPaymentToken(
        _ appUuid: String,
        _ payment: PKPayment,
        completion: @escaping (Result<ApplePayResponse?, Error>) -> Void
    ) {
        let url = Bundle.main.evervaultBaseURL
            .appendingPathComponent("/frontend/apple-pay/credentials")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appUuid, forHTTPHeaderField: "x-evervault-app-id")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        
        do {
            let decoded = try JSONDecoder()
                .decode(ApplePayToken.self, from: payment.token.paymentData)
            let requestBody = ApplePayPayload(
                isNative: true,
                encryptedCredentials: decoded
            )
            request.httpBody = try JSONEncoder().encode(requestBody)
        } catch {
            completion(.failure(EvervaultError.DecodingError(underlying: error)))
            return
        }
        
        let task = URLSession.shared.dataTask(with: request) { data, resp, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard
                let data = data,
                let http = resp as? HTTPURLResponse,
                (200...299).contains(http.statusCode)
            else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }
          
            do {
                let response = try JSONDecoder()
                    .decode(ApplePayResponse.self, from: data)
                completion(.success(response))
            } catch {
                completion(.failure(EvervaultError.DecodingError(underlying: error)))
            }
        }
        task.resume()
    }
}
