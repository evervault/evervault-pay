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

/// The three possible states of Apple Pay availability on a device.
public enum ApplePayAvailability: String, Codable, Sendable, Equatable {
    case available
    case unavailable
    case unsupported
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

    /// Outcome of the current attempt. `nil` here means the buyer cancelled.
    /// Only reported from `paymentAuthorizationViewControllerDidFinish`.
    private var tapAuthorizationOutcome: Result<Void, Error>?

    public weak var delegate: EvervaultPaymentViewDelegate? {
        didSet {
            // Verify Apple Pay is available on device
            if !PKPaymentAuthorizationViewController.canMakePayments() {
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
    @available(*, deprecated, message: "Use availability(supportedNetworks:) instead")
    public static func isAvailable() -> Bool {
        return PKPaymentAuthorizationViewController.canMakePayments()
    }

    /// Returns the three-state Apple Pay availability for the given supported card networks:
    /// `.unsupported` if the device can't do Apple Pay at all, `.unavailable` if it can but has
    /// no provisioned card on a supported network, `.available` otherwise.
    public static func availability(supportedNetworks: [Network]) -> ApplePayAvailability {
        return evaluateAvailability(
            deviceSupportsApplePay: PKPaymentAuthorizationViewController.canMakePayments(),
            hasCardForSupportedNetworks: PKPaymentAuthorizationViewController.canMakePayments(usingNetworks: supportedNetworks)
        )
    }

    nonisolated static func evaluateAvailability(deviceSupportsApplePay: Bool, hasCardForSupportedNetworks: Bool) -> ApplePayAvailability {
        if !deviceSupportsApplePay {
            return .unsupported
        }
        if !hasCardForSupportedNetworks {
            return .unavailable
        }
        return .available
    }

    struct MerchantDeclinedError: Error, LocalizedError {
        let underlying: Error

        var errorDescription: String? {
            "Merchant declined the payment: \(underlying.localizedDescription)"
        }
    }

    nonisolated static func resolveDisposition(for disposition: AuthorizationDisposition) -> Result<Void, Error> {
        switch disposition {
        case .success:
            return .success(())
        case .failure(let reason):
            return .failure(MerchantDeclinedError(underlying: reason))
        }
    }

    /// Records the disposition without notifying the delegate.
    /// Reporting is deferred to `paymentAuthorizationViewControllerDidFinish`.
    @MainActor
    func handleAuthorizationDisposition(_ disposition: AuthorizationDisposition) -> PKPaymentAuthorizationResult {
        self.tapAuthorizationOutcome = EvervaultPaymentView.resolveDisposition(for: disposition)
        switch disposition {
        case .success:
            // Tell Apple Pay the payment was successful
            return PKPaymentAuthorizationResult(status: .success, errors: nil)
        case .failure(let reason):
            // The merchant rejected the payment: surface back to Apple Pay as a failure
            return PKPaymentAuthorizationResult(status: .failure, errors: [reason])
        }
    }

    /// Records an SDK-level failure without notifying the delegate.
    /// Reporting is deferred to `paymentAuthorizationViewControllerDidFinish`.
    @MainActor
    func handleAuthorizationFailure(_ error: Error) -> PKPaymentAuthorizationResult {
        self.tapAuthorizationOutcome = .failure(EvervaultError.ApplePayAuthorizationError(underlying: error))
        // On error, surface back to Apple Pay
        return PKPaymentAuthorizationResult(status: .failure, errors: [error])
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
        // Reset before a new attempt.
        self.tapAuthorizationOutcome = nil

        // Update the transaction in place.
        self.delegate?.evervaultPaymentView(self, prepareTransaction: &self.transaction)
        
        do {
            let rootVC = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first(where: { $0.isKeyWindow })?.rootViewController
            
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
                    let vc: PKPaymentAuthorizationViewController?  = PKPaymentAuthorizationViewController(disbursementRequest: paymentRequest)
                    if vc == nil {
                        throw EvervaultError.ApplePayPaymentSheetError
                    }
                    vc?.delegate = self

                    // Present the Payment Sheet from the frontmost window
                    rootVC?.present(vc!, animated: true)
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
            default:
                if #available(iOS 16.0, *), case let .automaticReload(automaticReloadTransaction) = self.transaction {
                    let paymentRequest = self.buildPaymentRequest(transaction: automaticReloadTransaction)
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
    
    private func buildSummaryItems(for transaction: OneOffPaymentTransaction) -> [PKPaymentSummaryItem] {
        return transaction.paymentSummaryItems.map { item in
            PKPaymentSummaryItem(label: item.label, amount: item.amount.amount)
        }
    }

    private func buildSummaryItems(for transaction: RecurringPaymentTransaction) -> [PKPaymentSummaryItem] {
        var items = transaction.paymentSummaryItems.map { item in
            PKPaymentSummaryItem(label: item.label, amount: item.amount.amount)
        }
        items.append(transaction.regularBilling)
        if let trialBilling = transaction.trialBilling {
            items.append(trialBilling)
        }
        return items
    }

    private func buildSummaryItems(for transaction: DisbursementTransaction) -> [PKPaymentSummaryItem] {
        var items = transaction.paymentSummaryItems.map { item in
            PKPaymentSummaryItem(label: item.label, amount: item.amount.amount)
        }
        guard #available(iOS 17.0, *) else {
            // Disbursement requires iOS 17+ end-to-end - didTapPay() already refuses to create
            // a disbursement transaction below that, so this can't actually happen in practice.
            return items
        }
        if transaction.merchantCapability == .instantFundsOut, let instantOutFee = transaction.instantOutFee {
            items.append(PKInstantFundsOutFeeSummaryItem(label: instantOutFee.label, amount: instantOutFee.amount.amount))
        }
        items.append(PKDisbursementSummaryItem(
            label: transaction.disbursementItem.label,
            amount: transaction.disbursementItem.amount.amount
        ))
        return items
    }

    private func buildPaymentRequest(transaction: OneOffPaymentTransaction) -> PKPaymentRequest {
        let paymentRequest = PKPaymentRequest()
        paymentRequest.merchantIdentifier = self.appleMerchantIdentifier
        paymentRequest.supportedNetworks = self.supportedNetworks
        paymentRequest.countryCode = transaction.country
        paymentRequest.currencyCode = transaction.currency
        paymentRequest.paymentSummaryItems = self.buildSummaryItems(for: transaction)
        paymentRequest.merchantCapabilities = .threeDSecure

        paymentRequest.shippingType = transaction.shippingType
        paymentRequest.shippingMethods = transaction.shippingMethods
        paymentRequest.requiredShippingContactFields = transaction.requiredShippingContactFields
        paymentRequest.requiredBillingContactFields = transaction.requestPayerDetails
        paymentRequest.supportsCouponCode = transaction.supportsCouponCode
        paymentRequest.couponCode = transaction.couponCode

        if let billingContact = transaction.billingContact {
            paymentRequest.billingContact = PKContact(billingContact)
        }
        if let shippingContact = transaction.shippingContact {
            paymentRequest.shippingContact = PKContact(shippingContact)
        }

        return paymentRequest
    }

    @available(iOS 17.0, *)
    private func buildPaymentRequest(transaction: DisbursementTransaction) -> PKDisbursementRequest {
        let paymentRequest = PKDisbursementRequest()
        paymentRequest.merchantIdentifier = self.appleMerchantIdentifier
        paymentRequest.supportedNetworks = self.supportedNetworks
        paymentRequest.region = Locale.Region(transaction.country)
        paymentRequest.currency = Locale.Currency(transaction.currency)
        paymentRequest.summaryItems = self.buildSummaryItems(for: transaction)
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
        paymentRequest.paymentSummaryItems = self.buildSummaryItems(for: transaction)
        paymentRequest.merchantCapabilities = .threeDSecure

        let recurring = PKRecurringPaymentRequest(
            paymentDescription: transaction.paymentDescription,
            regularBilling: transaction.regularBilling,
            managementURL: transaction.managementURL
        )
        recurring.trialBilling = transaction.trialBilling
        recurring.billingAgreement = transaction.billingAgreement
        paymentRequest.recurringPaymentRequest = recurring
        paymentRequest.requiredBillingContactFields = transaction.requestPayerDetails
        paymentRequest.supportsCouponCode = transaction.supportsCouponCode
        paymentRequest.couponCode = transaction.couponCode

        paymentRequest.shippingType = transaction.shippingType
        paymentRequest.requiredShippingContactFields = transaction.requiredShippingContactFields

        if let billingContact = transaction.billingContact {
            paymentRequest.billingContact = PKContact(billingContact)
        }
        if let shippingContact = transaction.shippingContact {
            paymentRequest.shippingContact = PKContact(shippingContact)
        }

        return paymentRequest
    }

    // Reconstructs the real PassKit type here (rather than storing it on the model) so the model
    // stays iOS-15-safe. Shared by `buildPaymentRequest` and `getPaymentSummaryItems` so the reload
    // line item can't drift out of sync between what's shown initially and what's shown after
    // PassKit-triggered summary-item rebuilds (shipping/payment-method/coupon changes).
    @available(iOS 16.0, *)
    private static func buildAutomaticReloadBillingItem(transaction: AutomaticReloadPaymentTransaction) -> PKAutomaticReloadPaymentSummaryItem {
        let automaticReloadBilling = PKAutomaticReloadPaymentSummaryItem(
            label: transaction.automaticReloadBilling.label,
            amount: transaction.automaticReloadBilling.amount.amount
        )
        if let thresholdAmount = transaction.automaticReloadThresholdAmount {
            automaticReloadBilling.thresholdAmount = thresholdAmount.amount
        }
        return automaticReloadBilling
    }

    @available(iOS 16.0, *)
    private func buildPaymentRequest(transaction: AutomaticReloadPaymentTransaction) -> PKPaymentRequest {
        let paymentRequest = PKPaymentRequest()
        paymentRequest.merchantIdentifier = self.appleMerchantIdentifier
        paymentRequest.supportedNetworks = self.supportedNetworks
        paymentRequest.countryCode = transaction.country
        paymentRequest.currencyCode = transaction.currency
        paymentRequest.paymentSummaryItems = transaction.paymentSummaryItems.map { item in
            PKPaymentSummaryItem(label: item.label, amount: item.amount.amount)
        }
        paymentRequest.merchantCapabilities = .threeDSecure

        let automaticReloadBilling = Self.buildAutomaticReloadBillingItem(transaction: transaction)
        paymentRequest.paymentSummaryItems.append(automaticReloadBilling)
        let automaticReload = PKAutomaticReloadPaymentRequest(
            paymentDescription: transaction.paymentDescription,
            automaticReloadBilling: automaticReloadBilling,
            managementURL: transaction.managementURL
        )
        automaticReload.billingAgreement = transaction.billingAgreement
        paymentRequest.automaticReloadPaymentRequest = automaticReload
        paymentRequest.requiredBillingContactFields = transaction.requestPayerDetails
        paymentRequest.supportsCouponCode = transaction.supportsCouponCode
        paymentRequest.couponCode = transaction.couponCode

        paymentRequest.shippingType = transaction.shippingType
        paymentRequest.requiredShippingContactFields = transaction.requiredShippingContactFields

        if let billingContact = transaction.billingContact {
            paymentRequest.billingContact = PKContact(billingContact)
        }
        if let shippingContact = transaction.shippingContact {
            paymentRequest.shippingContact = PKContact(shippingContact)
        }

        return paymentRequest
    }

    private func getPaymentSummaryItems() -> [PKPaymentSummaryItem] {
        switch self.transaction {
        case let .oneOffPayment(oneOffTransaction):
            return self.buildSummaryItems(for: oneOffTransaction)
        case let .disbursement(dispersementTransaction):
            return self.buildSummaryItems(for: dispersementTransaction)
        case let .recurringPayment(recurringTransaction):
            return self.buildSummaryItems(for: recurringTransaction)
        default:
            // Covers .automaticReload, which can't be named directly here since it's
            // gated to iOS 16+ while this switch compiles at the package's iOS 15 minimum.
            if #available(iOS 16.0, *), case let .automaticReload(automaticReloadTransaction) = self.transaction {
                var items = automaticReloadTransaction.paymentSummaryItems.map { item in
                    PKPaymentSummaryItem(label: item.label, amount: item.amount.amount)
                }
                items.append(Self.buildAutomaticReloadBillingItem(transaction: automaticReloadTransaction))
                return items
            }
            return []
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
            let transactionType = try await MainActor.run { try ApplePayTransactionType(self.transaction) }
            let enriched = decoded?.enriched(
                billingContact: ApplePayContact(payment.billingContact),
                shippingContact: ApplePayContact(payment.shippingContact),
                transactionType: transactionType
            )
            await MainActor.run {
                // Notify the delegate on the main actor
                self.delegate?.evervaultPaymentView(self, didAuthorizePayment: enriched)
            }

            // Give the merchant a chance to approve or reject the decrypted payment before we report success.
            let disposition = await self.delegate?.evervaultPaymentView(self, shouldAuthorize: enriched) ?? .success(())
            return await self.handleAuthorizationDisposition(disposition)
        } catch {
            return await self.handleAuthorizationFailure(error)
        }
    }
    
    /// Called when the payment sheet is dismissed
    nonisolated public func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
        DispatchQueue.main.async { [weak self] in
            if let self = self {
                // Clear now, rather than leaving stale outcome until the next didTapPay() reset.
                defer { self.tapAuthorizationOutcome = nil }
                switch self.tapAuthorizationOutcome {
                case .success:
                    self.delegate?.evervaultPaymentView(self, didFinishWithResult: .success(()))
                case .failure(let error as MerchantDeclinedError):
                    // Pass the merchant's original error, not our wrapper.
                    self.delegate?.evervaultPaymentView(self, didDeclinePayment: error.underlying)
                case .failure(let evError as EvervaultError):
                    self.delegate?.evervaultPaymentView(self, didFinishWithResult: .failure(evError))
                case .failure(let error):
                    // Unreachable. Only MerchantDeclinedError/EvervaultError are ever stored.
                    assertionFailure("tapAuthorizationOutcome held an unrecognized error type: \(error)")
                    self.delegate?.evervaultPaymentView(self, didFinishWithResult: .failure(.InternalError(underlying: error)))
                case .none:
                    self.delegate?.evervaultPaymentViewDidCancel(self)
                }
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
    public func paymentAuthorizationViewController(_ controller: PKPaymentAuthorizationViewController, didSelect paymentMethod: PKPaymentMethod) async -> PKPaymentRequestPaymentMethodUpdate {
        return await self.delegate?.evervaultPaymentView(self, didUpdatePaymentMethod: paymentMethod) ?? PKPaymentRequestPaymentMethodUpdate(paymentSummaryItems: self.getPaymentSummaryItems())
    }

    @MainActor
    public func paymentAuthorizationViewController(
        _ controller: PKPaymentAuthorizationViewController,
        didChangeCouponCode couponCode: String
    ) async -> PKPaymentRequestCouponCodeUpdate {
        return await self.delegate?.evervaultPaymentView(self, didChangeCouponCode: couponCode) ?? PKPaymentRequestCouponCodeUpdate(paymentSummaryItems: self.getPaymentSummaryItems())
    }
}

// MARK: - Delegate Protocol

/// Delegate for receiving result callbacks from `EvervaultPaymentView`
public protocol EvervaultPaymentViewDelegate : AnyObject {
    /// Fired when a payment is authorized (but before dismissal)
    func evervaultPaymentView(_ view: EvervaultPaymentView, didAuthorizePayment result: ApplePayResponse?)

    /// Called after a payment is authorized, letting the merchant approve or reject it before the sheet reports success. Defaults to `.success` when not implemented.
    func evervaultPaymentView(_ view: EvervaultPaymentView, shouldAuthorize result: ApplePayResponse?) async -> AuthorizationDisposition

    /// Called when the user updates the shipping method.  The delegate returns an optional update which could include things like the re-calculated cost including shipping.
    func evervaultPaymentView(_ view: EvervaultPaymentView, didSelectShippingContact: PKContact) async -> PKPaymentRequestShippingContactUpdate?

    /// Called when the user updates the payment method.
    func evervaultPaymentView(_ view: EvervaultPaymentView, didUpdatePaymentMethod paymentMethod: PKPaymentMethod) async -> PKPaymentRequestPaymentMethodUpdate?

    /// Called when the user changes the coupon code on the Apple Pay sheet (only shown when `supportsCouponCode` is set on the transaction). The delegate returns an update with the re-calculated summary items, and can supply errors (e.g. via `PKPaymentRequest.paymentCouponCodeInvalidError`) to reject the code.
    func evervaultPaymentView(_ view: EvervaultPaymentView, didChangeCouponCode couponCode: String) async -> PKPaymentRequestCouponCodeUpdate?

    /// Fired when the payment sheet is fully dismissed with a genuine SDK-level outcome (not a merchant decline or buyer cancel)
    func evervaultPaymentView(_ view: EvervaultPaymentView, didFinishWithResult result: Result<Void, EvervaultError>)

    /// Fired when the buyer dismisses the sheet without ever authorizing a payment (e.g. taps Cancel), distinct from `didFinishWithResult`'s success/failure.
    func evervaultPaymentViewDidCancel(_ view: EvervaultPaymentView)

    /// Fired when the merchant rejects an authorized payment by returning `.failure(reason)` from `shouldAuthorize`, wrapping the reason they returned.
    /// Distinct from `didFinishWithResult`, which only reports genuine SDK-level outcomes.
    func evervaultPaymentView(_ view: EvervaultPaymentView, didDeclinePayment reason: Error)

    /// Called after the user taps the Apple Pay button, but before the modal is displayed.  The delegate can modify the transaction in-place.
    func evervaultPaymentView(_ view: EvervaultPaymentView, prepareTransaction transaction: inout Transaction)
}

// Default implementations, making these methods optional for a delegate to implement.
extension EvervaultPaymentViewDelegate {
    public func evervaultPaymentView(_ view: EvervaultPaymentView, prepareTransaction transaction: inout Transaction) {
        // Do nothing
    }

    public func evervaultPaymentView(_ view: EvervaultPaymentView, didFinishWithResult result: Result<Void, EvervaultError>) {
        // Do nothing
    }

    public func evervaultPaymentViewDidCancel(_ view: EvervaultPaymentView) {
        // Do nothing
    }

    public func evervaultPaymentView(_ view: EvervaultPaymentView, didDeclinePayment reason: Error) {
        // Do nothing
    }

    public func evervaultPaymentView(_ view: EvervaultPaymentView, shouldAuthorize result: ApplePayResponse?) async -> AuthorizationDisposition {
        return .success(())
    }

    public func evervaultPaymentView(_ view: EvervaultPaymentView, didSelectShippingContact: PKContact) async -> PKPaymentRequestShippingContactUpdate? {
        return nil
    }
    
    public func evervaultPaymentView(_ view: EvervaultPaymentView, didUpdatePaymentMethod paymentMethod: PKPaymentMethod) async -> PKPaymentRequestPaymentMethodUpdate? {
        return nil
    }

    public func evervaultPaymentView(_ view: EvervaultPaymentView, didChangeCouponCode couponCode: String) async -> PKPaymentRequestCouponCodeUpdate? {
        return nil
    }
}
