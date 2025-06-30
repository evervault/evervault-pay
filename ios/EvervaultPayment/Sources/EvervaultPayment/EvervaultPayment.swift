import UIKit
import PassKit
import PassKit
import Foundation

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
    public let buttonType: ButtonType
    public let buttonStyle: ButtonStyle
    public weak var delegate: EvervaultPaymentViewDelegate?

    /// The Apple Pay button
    private lazy var payButton: PKPaymentButton = {
        let button = PKPaymentButton(paymentButtonType: buttonType, paymentButtonStyle: buttonStyle)
        button.addTarget(self, action: #selector(didTapPay), for: .touchUpInside)
        return button
    }()
    
    // MARK: Init

    /// Designated initializer
    public init(
        appUuid: String,
        merchantIdentifier: String,
        transaction: Transaction,
        supportedNetworks: [Network],
        buttonStyle: ButtonStyle,
        buttonType: ButtonType,
    ) {
        self.appUuid = appUuid
        self.merchantIdentifier = merchantIdentifier
        self.transaction = transaction
        self.supportedNetworks = supportedNetworks
        self.buttonStyle = buttonStyle
        self.buttonType = buttonType

        // Verify Apple Pay is available on device
        guard PKPaymentAuthorizationViewController.canMakePayments() else {
            print("Error")
            super.init(frame: .zero)
            return
        }
        super.init(frame: .zero)
        setupLayout()
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
    
    /// Set the intrinsic size of this component to the underlying button size
    override public var intrinsicContentSize: CGSize {
        return payButton.intrinsicContentSize
    }

    /// Set the subview layout
    override public func layoutSubviews() {
        super.layoutSubviews()
        payButton.frame = bounds
    }

    /// Set up the layout
    private func setupLayout() {
        addSubview(payButton)
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

extension EvervaultPaymentView : PKPaymentAuthorizationViewControllerDelegate {
    /// Called when the user authorizes the payment
    nonisolated public func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didAuthorizePayment payment: PKPayment) async -> PKPaymentAuthorizationResult {
        do {
            // Send the token to the Evervault backend for decryption and re-encryption with Evervault Encryption
            let decoded = try await EvervaultApi.sendPaymentToken(appUuid, payment)
            await MainActor.run {
                // Notify the delegate on the main actor
                self.delegate?.evervaultPaymentView(self, didAuthorizePayment: decoded)
            }
            
            // Tell Apple Pay the payment was successful
            return PKPaymentAuthorizationResult(status: .success, errors: nil)
        } catch {
            await MainActor.run {
                // Notify the delegate on the main actor
                self.delegate?.evervaultPaymentView(self, didFinishWithError: error)
            }
            // On error, surface back to Apple Pay
            return PKPaymentAuthorizationResult(status: .failure, errors: [error])
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
    func evervaultPaymentView(_ view: EvervaultPaymentView, didFinishWithError error: Error?)
}
