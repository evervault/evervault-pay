import UIKit
import PassKit
import Foundation

// MARK: - Errors

/// Defines all possible errors in the Evervault Apple Pay flow.
public enum EvervaultError: Error, LocalizedError {
    case InvalidTransactionError
    case EmptyTransactionError
    case InvalidCurrencyError
    case InvalidCountryError
    case ApplePayUnavailableError
    case ApplePayPaymentSheetError
    case InternalError(underlying: Error)
    
    public var errorDescription: String? {
        switch self {
        case .InvalidTransactionError:
            return "A generic error occurred when processing the transaction."
        case .EmptyTransactionError:
            return "Transaction must contain at least 1 summary item."
        case .ApplePayUnavailableError:
            return "Apple Pay is unavailable on this device."
        case .ApplePayPaymentSheetError:
            return "An error occurred when presenting the Payment Sheet."
        case .InternalError(let underlying):
            return "An error occurred when handling the payment token: \(underlying)"
        case .InvalidCurrencyError:
            return "Invalid currency provided to the transaction"
        case .InvalidCountryError:
            return "Invalid country provided to the transaction"
        }
    }
}

// MARK: - Apple Pay View

/// A UIView that wraps Apple Pay button and handles full payment flow.
public class EvervaultPaymentView: UIView {
    public var appUuid: String
    public var appleMerchantIdentifier: String
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
        appId: String,
        appleMerchantId: String,
        transaction: Transaction,
        supportedNetworks: [Network],
        buttonStyle: ButtonStyle,
        buttonType: ButtonType
    ) {
        self.appUuid = appId
        self.appleMerchantIdentifier = appleMerchantId
        self.transaction = transaction
        self.supportedNetworks = supportedNetworks
        self.buttonStyle = buttonStyle
        self.buttonType = buttonType
        super.init(frame: .zero)

        // Verify Apple Pay is available on device
        guard PKPaymentAuthorizationViewController.canMakePayments() else {
            // defer until after init-time delegate assignment
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.evervaultPaymentView(
                    self,
                    didFinishWithError: EvervaultError.ApplePayUnavailableError
                )
            }
            return
        }
        
        setupLayout()
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
    }
    
    required init?(coder: NSCoder) {
        fatalError("EvervaultPaymentView must be created in code.")
    }
    
    /// Public check for Apple Pay availability
    public static func isAvailable() -> Bool {
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
    @objc private func didTapPay() {
        do {
            // Must have at least 1 line item
            guard !transaction.paymentSummaryItems.isEmpty else {
                throw EvervaultError.EmptyTransactionError
            }
            
            // Build the PKPaymentRequest from the Transaction
            let paymentRequest = buildPaymentRequest()
            // Create the authorization view controller
            guard let vc = PKPaymentAuthorizationViewController(paymentRequest: paymentRequest) else {
                throw EvervaultError.ApplePayPaymentSheetError
            }
            
            vc.delegate = self
            
            // Present the Payment Sheet from the frontmost window
            if let rootVC = UIApplication.shared.windows
                .first(where: { $0.isKeyWindow })?
                .rootViewController {
                    rootVC.present(vc, animated: true, completion: nil)
                }
        } catch {
            delegate?.evervaultPaymentView(self, didFinishWithError: error)
        }
    }
    
    /// Constructs the Apple Pay Payment request object
    private func buildPaymentRequest() -> PKPaymentRequest {
        let paymentRequest = PKPaymentRequest()
        paymentRequest.merchantIdentifier = self.appleMerchantIdentifier
        paymentRequest.supportedNetworks = self.supportedNetworks
        paymentRequest.countryCode = self.transaction.country
        paymentRequest.currencyCode = self.transaction.currency

        // Map our SummaryItem model to PKPaymentSummaryItem
        paymentRequest.paymentSummaryItems = paymentSummaryItemsForSummaryItems()
        paymentRequest.merchantCapabilities = .threeDSecure
        return paymentRequest
    }
    
    /// Constructs the Apple Pay Payment request object
    @available(iOS 17.0, *)
    private func buildDisbursementPaymentRequest() -> PKDisbursementRequest {
        let paymentRequest = PKDisbursementRequest()
        paymentRequest.merchantIdentifier = self.appleMerchantIdentifier
        paymentRequest.supportedNetworks = self.supportedNetworks
        paymentRequest.region = .init(self.transaction.country)
        paymentRequest.currency = .init(self.transaction.currency)

        // Map our SummaryItem model to PKPaymentSummaryItem
        paymentRequest.summaryItems = paymentSummaryItemsForSummaryItems()
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
    nonisolated public func paymentAuthorizationViewController(
        _ controller: PKPaymentAuthorizationViewController,
        didAuthorizePayment payment: PKPayment
    ) async -> PKPaymentAuthorizationResult {
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
    
    @MainActor
    public func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didSelect shippingMethod: PKShippingMethod) async -> PKPaymentRequestShippingMethodUpdate {
        return await self.delegate?.evervaultPaymentView(self, didUpdateShippingMethod: shippingMethod) ?? PKPaymentRequestShippingMethodUpdate(paymentSummaryItems: self.buildPaymentRequest().paymentSummaryItems)
    }
    
    @MainActor
    public func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didSelectPaymentMethod paymentMethod: PKPaymentMethod) async -> PKPaymentRequestPaymentMethodUpdate {
        return await self.delegate?.evervaultPaymentView(self, didUpdatePaymentMethod: paymentMethod) ?? PKPaymentRequestPaymentMethodUpdate(paymentSummaryItems: self.buildPaymentRequest().paymentSummaryItems)
    }
}

// MARK: - Delegate Protocol

/// Delegate for receiving result callbacks from `EvervaultPaymentView`
public protocol EvervaultPaymentViewDelegate : AnyObject {
    /// Fired when a payment is authorized (but before dismissal)
    func evervaultPaymentView(_ view: EvervaultPaymentView, didAuthorizePayment result: ApplePayResponse?)

    func evervaultPaymentView(_ view: EvervaultPaymentView, didUpdateShippingMethod shippingMethod: PKShippingMethod) async -> PKPaymentRequestShippingMethodUpdate?
    func evervaultPaymentView(_ view: EvervaultPaymentView, didUpdatePaymentMethod paymentMethod: PKPaymentMethod) async -> PKPaymentRequestPaymentMethodUpdate?

    /// Fired when the payment sheet is fully dismissed
    func evervaultPaymentView(_ view: EvervaultPaymentView, didFinishWithResult result: String?)
    func evervaultPaymentView(_ view: EvervaultPaymentView, didFinishWithError error: Error?)
}
