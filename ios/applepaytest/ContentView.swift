//
//  ContentView.swift
//  applepaytest
//
//  Created by Jake Grogan on 14/05/2025.
//

import SwiftUI
import PassKit
import Foundation

let request = buildPaymentRequest()
let MERCHANT_IDENTIFIER = "merchant.com.example.test"


struct EvervaultApi {
    static func sendPaymentToken(_ token: PKPaymentToken) async throws -> Data {
        // This is just a sample. Normally you'd encode token.paymentData, but http.cat/200 doesn't care!
        let url = URL(string: "https://meowfacts.herokuapp.com/")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // If you wanted to send the token, you could POST with token.paymentData as the body.
        // For http.cat/200, we just GET.
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        return data
    }
}

func buildPaymentRequest() -> Transaction {
    let x = NSDecimalNumber(string: "5")
    print(x.doubleValue)

    let transaction = Transaction(
        currency: "CLP",
        country: "JP",
        supportedNetworks: [.visa, .masterCard, .amex],
        paymentSummaryItems: [
            SummaryItem(label: "Test Item", amount: NSDecimalNumber(string: "1")),
            SummaryItem(label: "Test Item 2", amount: NSDecimalNumber(string: "3")),
            SummaryItem(label: "Total", amount: x)
        ]
    )
    return transaction
}

struct ContentView: View {
    @State private var paymentResult: String?
    
    var body: some View {
        VStack {
            Text("Apple Pay Test")
                .font(.title)
                .padding()
            
            EvervaultPayment(merchantIdentifier: MERCHANT_IDENTIFIER, paymentRequest: request)
                .onResult { result in
                    paymentResult = result
                }
                .frame(width: 200, height: 44)

            if let paymentResult {
                Text("Payment Result: \(paymentResult)")
            }
        }
    }
}

typealias Network = PKPaymentNetwork

typealias SummaryItem = PKPaymentSummaryItem

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

struct EvervaultPayment: UIViewRepresentable {
    var merchantIdentifier: String;
    let paymentRequest: Transaction
    var onResult: ((String?) -> Void)?

    func makeUIView(context: Context) -> PKPaymentButton {
        let button = PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .black)
        button.addTarget(context.coordinator, action: #selector(Coordinator.didTapPay), for: .touchUpInside)
        return button
    }
    
    func updateUIView(_ uiView: PKPaymentButton, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(parent: self)
    }
    
    func onResult(_ action: @escaping (String?) -> Void) -> EvervaultPayment {
        var copy = self
        copy.onResult = action
        return copy
    }
    
    class Coordinator: NSObject, PKPaymentAuthorizationViewControllerDelegate {
        private let parent: EvervaultPayment
        
        init(parent: EvervaultPayment) {
            self.parent = parent
        }
        
        @objc func didTapPay() {
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
            Task {
                    do {
                        // Example: your async network call
                        let result = try await EvervaultApi.sendPaymentToken(payment.token)
                        // handle success, maybe check result
                        let text = String(data: result, encoding: .utf8)
                        await parent.onResult?(text)
                        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
                    } catch {
                        // handle error
                        await parent.onResult?(nil)
                        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
                    }
                }
            
        }
        
        func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
            controller.dismiss(animated: true, completion: nil)
        }
    }
}
