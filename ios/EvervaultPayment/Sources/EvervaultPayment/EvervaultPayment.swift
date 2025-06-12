// The Swift Programming Language
// https://docs.swift.org/swift-book

import UIKit
import PassKit
import PassKit
import Foundation

struct EvervaultApi {
    static func sendPaymentToken(_ token: PKPayment) async throws -> String? {
        guard let url = URL(string: "https://meowfacts.herokuapp.com/") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        // Check for HTTP 2xx
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        // Decode JSON response
        return String(data: data, encoding: .utf8)
    }
}

typealias Network = PKPaymentNetwork

typealias SummaryItem = PKPaymentSummaryItem

public struct Transaction {
    let paymentRequest: PKPaymentRequest

    init(currency: String, country: String, supportedNetworks: [Network], paymentSummaryItems: [SummaryItem]) {
        self.paymentRequest = PKPaymentRequest()
        self.paymentRequest.countryCode = country
        self.paymentRequest.currencyCode = currency
        self.paymentRequest.supportedNetworks = supportedNetworks
        self.paymentRequest.paymentSummaryItems = paymentSummaryItems
        self.paymentRequest.merchantCapabilities = .threeDSecure
    }
}

public class EvervaultPaymentView: UIView {
    public var merchantIdentifier: String
    public let paymentRequest: Transaction
    public weak var delegate: EvervaultPaymentViewDelegate?

    private lazy var payButton: PKPaymentButton = {
        let button = PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .black)
        button.addTarget(self, action: #selector(didTapPay), for: .touchUpInside)
        return button
    }()
    
    public init(
        merchantIdentifier: String,
        paymentRequest: Transaction,
    ) {
        self.merchantIdentifier = merchantIdentifier
        self.paymentRequest = paymentRequest
        super.init(frame: .zero)
        setupLayout()
    }
    
    // Why is this required?
    required init?(coder: NSCoder) {
        fatalError("EvervaultPaymentView must be created in code.")
    }
    
    private func setupLayout() {
        addSubview(payButton)
        payButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            payButton.topAnchor.constraint(equalTo: topAnchor),
            payButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            payButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            payButton.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }
    
    @objc private func didTapPay() {
        guard PKPaymentAuthorizationViewController.canMakePayments() else {
            print("Apple Pay unavailable.")
            return
        }
        guard let vc = PKPaymentAuthorizationViewController(paymentRequest: self.paymentRequest.paymentRequest) else {
            print("Failed to create Apple Pay sheet.")
            return
        }

        vc.delegate = self
        
        // 3) Present from the frontmost window’s rootVC
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(vc, animated: true, completion: nil)
        }
    }
}

extension EvervaultPaymentView : PKPaymentAuthorizationViewControllerDelegate {
    nonisolated public func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment) async -> PKPaymentAuthorizationResult {
        do {
            let decoded = try await EvervaultApi.sendPaymentToken(payment)
            await MainActor.run {
                self.delegate?.evervaultPaymentView(self, didAuthorizePayment: decoded ?? "test")
            }

            return PKPaymentAuthorizationResult(status: .success, errors: nil)
        } catch {
            return PKPaymentAuthorizationResult(status: .success, errors: [error])
        }
    }
    
    nonisolated public func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.evervaultPaymentView(self!, didFinishWithResult: nil)
        }
        
    }
}

public protocol EvervaultPaymentViewDelegate : AnyObject {
    func evervaultPaymentView(_ view: EvervaultPaymentView, didAuthorizePayment result: String?)
    func evervaultPaymentView(_ view: EvervaultPaymentView, didFinishWithResult result: String?)
}
