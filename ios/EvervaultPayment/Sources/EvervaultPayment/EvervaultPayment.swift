// The Swift Programming Language
// https://docs.swift.org/swift-book
import SwiftUI
import PassKit
import Foundation

struct EvervaultApi {
    @available(macOS 12.0, *)
    static func sendPaymentToken(_ token: Data, completion: @escaping (Result<Data, Error>) -> Void) {
            let url = URL(string: "https://meowfacts.herokuapp.com/")!
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard
                    let data = data,
                    let httpResponse = response as? HTTPURLResponse,
                    httpResponse.statusCode == 200
                else {
                    completion(.failure(URLError(.badServerResponse)))
                    return
                }
                completion(.success(data))
            }.resume()
        }
}

typealias Network = PKPaymentNetwork

typealias SummaryItem = PKPaymentSummaryItem

@available(macOS 11.0, *)
class Transaction {
    var paymentRequest: PKPaymentRequest;
    
    init(currency: String, country: String, supportedNetworks: [Network], paymentSummaryItems: [SummaryItem]) {
        self.paymentRequest = PKPaymentRequest()
        self.paymentRequest.countryCode = country
        self.paymentRequest.currencyCode = currency
        self.paymentRequest.supportedNetworks = supportedNetworks
        self.paymentRequest.paymentSummaryItems = paymentSummaryItems
        self.paymentRequest.merchantCapabilities = .threeDSecure
    }
}

@available(macOS 11.0, *)
struct EvervaultPayment: UIViewRepresentable {
    var merchantIdentifier: String;
    let paymentRequest: Transaction
    var onResult: (@Sendable (String?) -> Void)?

    @MainActor @available(macOS 11.0, *)
    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.didTapPay), for: .touchUpInside)
        return button
    }
    
    @available(macOS 11.0, *)
    func updateUIView(_ uiView: PKPaymentButton, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, PKPaymentAuthorizationViewControllerDelegate {
        private let parent: EvervaultPayment
        
        init(parent: EvervaultPayment) {
            self.parent = parent
        }
        
        @MainActor @objc func didTapPay() {
            let request = parent.paymentRequest.paymentRequest
            let merchantIdentifier = parent.merchantIdentifier
            
            request.merchantIdentifier = merchantIdentifier

            guard PKPaymentAuthorizationViewController.canMakePayments() else {
                print("Apple Pay not available on this device.")
                return
            }
            
            guard let paymentVC = PKPaymentAuthorizationViewController(paymentRequest: request) else {
                print("Unable to present Apple Pay sheet.")
                return
            }
            paymentVC.delegate = self
            
            if let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(paymentVC, animated: true, completion: nil)
            }
        }


        func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment, handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
            print("Authorized payment: \(payment)")
        
            print("Token: \(payment.token)")
            print("Token: \(payment.token.paymentData)")
            let paymentToken = payment.token.paymentData
            let parentOnResult = self.parent.onResult
            EvervaultApi.sendPaymentToken(paymentToken) { result in
                // Switch to main thread for UI and Apple Pay completion
                switch result {
                case .success(let data):
                    let text = String(data: data, encoding: .utf8)
                    parentOnResult?(text)
                    completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
                case .failure(_):
                    parentOnResult?("text")
                    completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
                }
            }
        }
        
        func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
            DispatchQueue.main.async {
                controller.dismiss(animated: true, completion: nil)
            }
        }
    }
}
