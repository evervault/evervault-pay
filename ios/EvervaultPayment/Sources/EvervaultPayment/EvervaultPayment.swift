import UIKit
import PassKit
//import Foundation

// MARK: - Errors

/// Defines all possible errors in the Evervault Apple Pay flow.
public enum EvervaultError: Error, LocalizedError {
    case InvalidTransactionError
    case ApplePayUnavailableError
    case ApplePayPaymentSheetError
    case DecodingError(underlying: Error)
    
    public var errorDescription: String? {
        switch self {
        case .InvalidTransactionError:
            return "Transaction must contain at least 1 summary item."
        case .ApplePayUnavailableError:
            return "Apple Pay is unavailable on this device."
        case .ApplePayPaymentSheetError:
            return "An error occurred when presenting the Payment Sheet."
        case .DecodingError(let underlying):
            return "Failed to decode response from Evervault when encrypting the payment token: \(underlying)"
        }
    }
}

// MARK: - Apple Pay View

/// A UIView that wraps Apple Pay button and handles full payment flow.
public class EvervaultPaymentView: UIView {
    public var appUuid: String
    public var merchantIdentifier: String
    public let transaction: Transaction
    public let supportedNetworks: [Network]
    public weak var delegate: EvervaultPaymentViewDelegate?

    /// The Apple Pay button
    private lazy var payButton: PKPaymentButton = {
        let button = PKPaymentButton(paymentButtonType: .buy, paymentButtonStyle: .black)
        button.addTarget(self, action: #selector(didTapPay), for: .touchUpInside)
        return button
    }()
    
    // MARK: Init

    /// Designated initializer
    public init(
        appUuid: String,
        merchantIdentifier: String,
        transaction: Transaction,
        supportedNetworks: [Network]
    ) {
        self.appUuid = appUuid
        self.merchantIdentifier = merchantIdentifier
        self.transaction = transaction
        self.supportedNetworks = supportedNetworks
        // Verify Apple Pay is available on device
//        guard PKPaymentAuthorizationViewController.canMakePayments() else {
//            print("Error")
//            let isSandboxed = (ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil)
//            print(isSandboxed)
//            super.init(frame: .zero)
//            return
//        }
        super.init(frame: .zero)
        print(payButton.intrinsicContentSize)
        setupLayout()
        print(payButton.intrinsicContentSize)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }
    
    required init?(coder: NSCoder) {
        fatalError("EvervaultPaymentView must be created in code.")
    }
    
    /// Public check for Apple Pay availability
    public func isAvailable() -> Bool {
        return PKPaymentAuthorizationViewController.canMakePayments()
    }
    
    // MARK: Layout

    /// Adds and constraints the pay button to fill the view
    private func setupLayout() {
        addSubview(payButton)
        payButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            payButton.topAnchor.constraint(equalTo: layoutMarginsGuide.topAnchor),
            payButton.bottomAnchor.constraint(equalTo: layoutMarginsGuide.bottomAnchor),
            payButton.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            payButton.trailingAnchor.constraint(equalTo: layoutMarginsGuide.trailingAnchor)
        ])
    }
    
    // Default size for the button
    public override var intrinsicContentSize: CGSize {
        return CGSize(width: 200, height: 44)
    }
    
    // MARK: Actions

    /// Tapped handler to start the Apple Pay sheet
    @objc private func didTapPay() throws {
        // Build the PKPaymentRequest from the Transaction
        let paymentRequest = buildPaymentRequest()
        // Create the authorization view controller
        guard let vc = PKPaymentAuthorizationViewController(paymentRequest: paymentRequest) else {
            throw EvervaultError.ApplePayPaymentSheetError
        }

        vc.delegate = self
        
        // Present the Payment Sheet from the frontmost window
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(vc, animated: true, completion: nil)
        }
    }
    
    /// Constructs the Apple Pay Payment request object
    private func buildPaymentRequest() -> PKPaymentRequest {
        let paymentRequest = PKPaymentRequest()
        paymentRequest.merchantIdentifier = self.merchantIdentifier
        paymentRequest.supportedNetworks = self.supportedNetworks
        paymentRequest.countryCode = self.transaction.country
        paymentRequest.currencyCode = self.transaction.currency
        // Map our SummaryItem model to PKPaymentSummaryItem
        paymentRequest.paymentSummaryItems = paymentSummaryItemsForSummaryItems()
        paymentRequest.merchantCapabilities = .threeDSecure
        return paymentRequest
    }
    
    /// Converts our `SummaryItem` array into PassKit summary items
    private func paymentSummaryItemsForSummaryItems() -> [PKPaymentSummaryItem] {
        let summaryItems = self.transaction.paymentSummaryItems.map { item in
            PKPaymentSummaryItem(label: item.label, amount: item.amount.amount)
        }
        return summaryItems
    }
}

// MARK: - Apple Pay Delegate

public struct PaymentHeader: Codable {
    public var ephemeralPublicKey: String
    public var publicKeyHash: String
    public var transactionId: String
}

public struct PaymentData: Codable {
    public var data: String
    public var signature: String
    public var version: String
    public var header: PaymentHeader
}

extension EvervaultPaymentView : PKPaymentAuthorizationViewControllerDelegate {
    /// Called when the user authorizes the payment
    nonisolated public func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment) async -> PKPaymentAuthorizationResult {
        do {
            if let json = try? JSONSerialization.jsonObject(with: payment.token.paymentData) as? [String: Any] {
                print(json)
            }
            let paymentData = """
                {
                    "data": "Bdno50lau0qMKDe2JhZ3C5bkOaks9Eh1/UgXh8EbjRo45Qqpm21uIhOci8dL9rRIVXcQ3cSPmkIPr18KyNuCqWwmkkhwnGUt+wsZ5wL2oipIjg9E/Bwdm9v4eW7P3nmVVUgdCHj0YIudrgt2y4zmcwY4EIrOBRdBM0yf1fdpIdBKrHnKJ+j6zcVeihOKfXcOqCyfXGGd+wpWf0MZUVKa2gTW21wg4Gbnv9eMVrJymc2pDh1oYZgYZwgTCPm/3R8IfQqUgq5NhiXEY6B2R55G45MPyiJkgIRZ0Uv5s46VaOONI7ExiqMKiY6sXPpR1QfOhnm7F55gcJBntJHkZ1Sfd/iHYzQTdpk/JD6V1nSoOLdn3RRYQqjgf/PVMktqhiCGBXRNPUzfLTbuj4r3",
                    "header": {
                      "ephemeralPublicKey": "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEeU9FQrPm92b4h/LMCxsu3Xcv4s1B8QGSTP1d/aw3u+X/6h+WGanOX+p6u+GMdHg79GJhGuGBOLsiDYPNJ8kbeQ==",
                      "publicKeyHash": "kujUp8ExcZq8qQQaPZo1CudXe3ijS96rEyp6CbTiuSU=",
                      "transactionId": "576e5562c4ec1649f0e1ea627dcc10c0be2471134d7e6381b411c4e781c4ea7c"
                    },
                    "signature": "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",
                    "version": "EC_v1"
                }
                """
            
            let paymentDataData = Data(paymentData.utf8)
            let jsonDecoder = JSONDecoder()
            
            let jsonData: PaymentData = try! jsonDecoder.decode(PaymentData.self, from: paymentDataData)
            print("Person -- \(jsonData.signature) was decode and their age is: \(jsonData.header)")
            
            
            // Send the token to the Evervault backend for decryption and re-encryption with Evervault Encryption
            let decoded = try await EvervaultApi.sendPaymentToken(appUuid, jsonData)
            await MainActor.run {
                // Notify the delegate on the main actor
                self.delegate?.evervaultPaymentView(self, didAuthorizePayment: decoded)
            }
            
            // Tell Apple Pay the payment was successful
            return PKPaymentAuthorizationResult(status: .success, errors: nil)
        } catch {
            // On error, surface back to Apple Pay
            return PKPaymentAuthorizationResult(status: .success, errors: [error])
        }
    }

    /// Called when the payment sheet is dismissed
    nonisolated public func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.evervaultPaymentView(self!, didFinishWithResult: nil)
            controller.dismiss(animated: true)
        }
    }
}

// MARK: - Delegate Protocol

/// Delegate for receiving result callbacks from `EvervaultPaymentView`
public protocol EvervaultPaymentViewDelegate : AnyObject {
    // Fired when a payment is authorized (but before dismissal)
    func evervaultPaymentView(_ view: EvervaultPaymentView, didAuthorizePayment result: ApplePayResponse?)
    /// Fired when the payment sheet is fully dismissed
    func evervaultPaymentView(_ view: EvervaultPaymentView, didFinishWithResult result: String?)
}
