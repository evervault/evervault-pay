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
    case UnsupportedVersionError
    case ApplePayAuthorizationError(underlying: Error)
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
        case .UnsupportedVersionError:
            return "Some functionality is not available on this version of iOS"
        case .ApplePayAuthorizationError(underlying: let underlying):
            return "Apple Pay failed to authorize: \(underlying)"
        }
    }
}

// MARK: - Apple Pay View

/// A UIView that wraps Apple Pay button and handles full payment flow.
public class EvervaultPaymentView: UIView {
    public var appUuid: String
    public var appleMerchantIdentifier: String
    private(set) var transaction: Transaction
    public let supportedNetworks: [Network]
    public let buttonType: ButtonType
    public let buttonStyle: ButtonStyle
    
    public weak var delegate: EvervaultPaymentViewDelegate? {
        didSet {
            // Verify Apple Pay is available on device
            if !EvervaultPaymentView.isAvailable() {
                self.delegate?.evervaultPaymentView(self, didFinishWithResult: .failure(.ApplePayUnavailableError))
            }
        }
    }
    
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
            // Notify the delegate after it is set.
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
        // Update the transaction in place.
        self.delegate?.evervaultPaymentView(self, prepareTransaction: &self.transaction)
        
        do {
            let rootVC = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController
            
            switch self.transaction {
            case let .oneOffPayment(oneOffTransaction):
                // Must have at least 1 line item
                guard !oneOffTransaction.paymentSummaryItems.isEmpty else {
                    throw EvervaultError.EmptyTransactionError
                }
                
                let paymentRequest = self.buildPaymentRequest(transaction: oneOffTransaction)
                guard let vc = PKPaymentAuthorizationViewController(paymentRequest: paymentRequest) else {
                    throw EvervaultError.ApplePayPaymentSheetError
                }
                vc.delegate = self
                
                // Present the Payment Sheet from the frontmost window
                rootVC?.present(vc, animated: true)
            case let .disbursement(disbursementTransaction):
                // Must have at least 1 line item
                guard !disbursementTransaction.paymentSummaryItems.isEmpty else {
                    throw EvervaultError.EmptyTransactionError
                }
                
                if #available(iOS 17.0, *) {
                    let paymentRequest = self.buildPaymentRequest(transaction: disbursementTransaction)
                    let vc = PKPaymentAuthorizationViewController(disbursementRequest: paymentRequest)
                    if vc == nil {
                        throw EvervaultError.ApplePayPaymentSheetError
                    }
                    vc.delegate = self
                    
                    // Present the Payment Sheet from the frontmost window
                    rootVC?.present(vc, animated: true)
                } else {
                    throw EvervaultError.UnsupportedVersionError
                }
            case let .recurringPayment(recurringTransaction):
                if #available(iOS 16.0, *) {
                    let paymentRequest = self.buildPaymentRequest(transaction: recurringTransaction)
                    guard let vc = PKPaymentAuthorizationViewController(paymentRequest: paymentRequest) else {
                        throw EvervaultError.ApplePayPaymentSheetError
                    }
                    vc.delegate = self
                    
                    // Present the Payment Sheet from the frontmost window
                    rootVC?.present(vc, animated: true)
                } else {
                    throw EvervaultError.UnsupportedVersionError
                }
            }
        } catch {
            if let evError = error as? EvervaultError {
                self.delegate?.evervaultPaymentView(self, didFinishWithResult: .failure(evError))
            } else {
                self.delegate?.evervaultPaymentView(self, didFinishWithResult: .failure(.InternalError(underlying: error)))
            }
        }
    }
    
    private func buildPaymentRequest(transaction: OneOffPaymentTransaction) -> PKPaymentRequest {
        let paymentRequest = PKPaymentRequest()
        paymentRequest.merchantIdentifier = self.appleMerchantIdentifier
        paymentRequest.supportedNetworks = self.supportedNetworks
        paymentRequest.countryCode = transaction.country
        paymentRequest.currencyCode = transaction.currency
        paymentRequest.paymentSummaryItems = transaction.paymentSummaryItems.map { item in
            PKPaymentSummaryItem(label: item.label, amount: item.amount.amount)
        }
        paymentRequest.merchantCapabilities = .threeDSecure
        
        paymentRequest.shippingType = transaction.shippingType
        paymentRequest.shippingMethods = transaction.shippingMethods
        paymentRequest.requiredShippingContactFields = transaction.requiredShippingContactFields
        
        return paymentRequest
    }
    
    @available(iOS 17.0, *)
    private func buildPaymentRequest(transaction: DisbursementTransaction) -> PKDisbursementRequest {
        let paymentRequest = PKDisbursementRequest()
        paymentRequest.merchantIdentifier = self.appleMerchantIdentifier
        paymentRequest.supportedNetworks = self.supportedNetworks
        paymentRequest.region = Locale.Region(transaction.country)
        paymentRequest.currency = Locale.Currency(transaction.currency)
        paymentRequest.summaryItems = transaction.paymentSummaryItems.map { item in
            PKPaymentSummaryItem(
                label: item.label,
                amount: item.amount.amount
            )
        }
        if transaction.merchantCapability == .instantFundsOut {
            if let instantOutFee = transaction.instantOutFee {
                paymentRequest.summaryItems.append(
                    PKInstantFundsOutFeeSummaryItem(
                        label: instantOutFee.label,
                        amount: instantOutFee.amount.amount
                    )
                )
            }
        }
        paymentRequest.summaryItems.append(
            PKDisbursementSummaryItem(
                label: transaction.disbursementItem.label,
                amount: transaction.disbursementItem.amount.amount
            )
        )
        paymentRequest.merchantCapabilities = transaction.merchantCapability
        paymentRequest.requiredRecipientContactFields = transaction.requiredRecipientDetails
        
        return paymentRequest
    }
    
    @available(iOS 16.0, *)
    private func buildPaymentRequest(transaction: RecurringPaymentTransaction) -> PKPaymentRequest {
        let paymentRequest = PKPaymentRequest()
        paymentRequest.merchantIdentifier = self.appleMerchantIdentifier
        paymentRequest.supportedNetworks = self.supportedNetworks
        paymentRequest.countryCode = transaction.country
        paymentRequest.currencyCode = transaction.currency
        paymentRequest.paymentSummaryItems = transaction.paymentSummaryItems.map { item in
            PKPaymentSummaryItem(label: item.label, amount: item.amount.amount)
        }
        paymentRequest.merchantCapabilities = .threeDSecure
        
        paymentRequest.paymentSummaryItems.append(transaction.regularBilling)
        if (transaction.trialBilling != nil) {
            paymentRequest.paymentSummaryItems.append(transaction.trialBilling!)
        }
        let recurring = PKRecurringPaymentRequest(
            paymentDescription: transaction.paymentDescription,
            regularBilling: transaction.regularBilling,
            managementURL: transaction.managementURL
        )
        recurring.trialBilling = transaction.trialBilling
        recurring.billingAgreement = transaction.billingAgreement
        paymentRequest.recurringPaymentRequest = recurring
        
        return paymentRequest
    }
    
    private func getPaymentSummaryItems() -> [PKPaymentSummaryItem] {
        switch self.transaction {
        case let .oneOffPayment(oneOffTransaction):
            return oneOffTransaction.paymentSummaryItems.map { item in
                PKPaymentSummaryItem(label: item.label, amount: item.amount.amount)
            }
        case let .disbursement(dispersementTransaction):
            return dispersementTransaction.paymentSummaryItems.map { item in
                PKPaymentSummaryItem(label: item.label, amount: item.amount.amount)
            }
        case let .recurringPayment(recurringTransaction):
            return recurringTransaction.paymentSummaryItems.map { item in
                PKPaymentSummaryItem(label: item.label, amount: item.amount.amount)
            }
        }
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
                self.delegate?.evervaultPaymentView(self, didFinishWithResult: .failure(.ApplePayAuthorizationError(underlying: error)))
            }
            // On error, surface back to Apple Pay
            return PKPaymentAuthorizationResult(status: .failure, errors: [error])
        }
    }
    
    /// Called when the payment sheet is dismissed
    nonisolated public func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        DispatchQueue.main.async { [weak self] in
            if let self = self {
                self.delegate?.evervaultPaymentView(self, didFinishWithResult: .success(()))
            }
            controller.dismiss(animated: true)
        }
    }
    
    @MainActor
    public func paymentAuthorizationViewController(
        _ controller: PKPaymentAuthorizationViewController,
        didSelectShippingContact contact: PKContact
    ) async -> PKPaymentRequestShippingContactUpdate {
        return await self.delegate?.evervaultPaymentView(self, didSelectShippingContact: contact) ?? PKPaymentRequestShippingContactUpdate(paymentSummaryItems: self.getPaymentSummaryItems())
    }
    
    @MainActor
    public func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didSelectPaymentMethod paymentMethod: PKPaymentMethod) async -> PKPaymentRequestPaymentMethodUpdate {
        return await self.delegate?.evervaultPaymentView(self, didUpdatePaymentMethod: paymentMethod) ?? PKPaymentRequestPaymentMethodUpdate(paymentSummaryItems: self.getPaymentSummaryItems())
    }
}

// MARK: - Delegate Protocol

/// Delegate for receiving result callbacks from `EvervaultPaymentView`
public protocol EvervaultPaymentViewDelegate : AnyObject {
    /// Fired when a payment is authorized (but before dismissal)
    func evervaultPaymentView(_ view: EvervaultPaymentView, didAuthorizePayment result: ApplePayResponse?)
    
    /// Called when the user updates the shipping method.  The delegate returns an optional update which could include things like the re-calculated cost including shipping.
    func evervaultPaymentView(_ view: EvervaultPaymentView, didSelectShippingContact: PKContact) async -> PKPaymentRequestShippingContactUpdate?
    
    /// Called when the user updates the payment method.
    func evervaultPaymentView(_ view: EvervaultPaymentView, didUpdatePaymentMethod paymentMethod: PKPaymentMethod) async -> PKPaymentRequestPaymentMethodUpdate?
    
    /// Fired when the payment sheet is fully dismissed
    func evervaultPaymentView(_ view: EvervaultPaymentView, didFinishWithResult result: Result<Void, EvervaultError>)
    
    /// Called after the user taps the Apple Pay button, but before the modal is displayed.  The delegate can modify the transaction in-place.
    func evervaultPaymentView(_ view: EvervaultPaymentView, prepareTransaction transaction: inout Transaction)
}

// Default implementations, making these methods optional for a delegate to implement.
extension EvervaultPaymentViewDelegate {
    public func evervaultPaymentView(_ view: EvervaultPaymentView, prepareTransaction transaction: inout Transaction) {
        // Do nothing
    }
    
    func evervaultPaymentView(_ view: EvervaultPaymentView, didFinishWithResult result: Result<Void, EvervaultError>) {
        // Do nothing
    }
    
    public func evervaultPaymentView(_ view: EvervaultPaymentView, didSelectShippingContact: PKContact) async -> PKPaymentRequestShippingContactUpdate? {
        return nil
    }
    
    public func evervaultPaymentView(_ view: EvervaultPaymentView, didUpdatePaymentMethod paymentMethod: PKPaymentMethod) async -> PKPaymentRequestPaymentMethodUpdate? {
        return nil
    }
}
