//
//  EvervaultPayment+SwiftUI.swift
//  EvervaultPayment
//
//  Created by Jake Grogan on 12/06/2025.
//

import SwiftUI
import PassKit

public typealias ButtonType = PKPaymentButtonType
public typealias ButtonStyle = PKPaymentButtonStyle

/// A SwiftUI‐friendly wrapper around your UIKit EvervaultPaymentView.
public struct EvervaultPaymentViewRepresentable: UIViewRepresentable {

    // MARK: Inputs
    let appUuid: String
    let appleMerchantIdentifier: String
    let transaction: Transaction
    let supportedNetworks: [Network]

    let buttonType: ButtonType
    let buttonStyle: ButtonStyle

    public init(
        appId: String,
        appleMerchantId: String,
        transaction: Transaction,
        supportedNetworks: [Network],
        buttonStyle: ButtonStyle = .automatic,
        buttonType: ButtonType = .buy,
        authorizedResponse: Binding<ApplePayResponse?>,
        onResult: @escaping (_ result: Result<Void, EvervaultError>) -> Void
    ) {
        self.appUuid = appId
        self.appleMerchantIdentifier = appleMerchantId
        self.transaction = transaction
        self.supportedNetworks = supportedNetworks
        self.buttonStyle = buttonStyle
        self.buttonType = buttonType

        self._authorizedResponse = authorizedResponse
        self.onResultCallback = onResult
    }

    /// Called when Apple Pay authorizes the payment
    @Binding var authorizedResponse: ApplePayResponse?

    /// Called when the sheet is dismissed
    private var onResultCallback: (_ result: Result<Void, EvervaultError>) -> Void
    private var onShippingAddressChangeCallback: ((_ shippingContact: PKContact) -> [SummaryItem])?
    private var onPaymentMethodChangeCallback: ((_ paymentMethod: PKPaymentMethod) -> PKPaymentRequestPaymentMethodUpdate)?
    private var onCouponCodeChangeCallback: ((_ couponCode: String) -> PKPaymentRequestCouponCodeUpdate)?
    private var onShippingMethodChangeCallback: ((_ shippingMethod: PKShippingMethod) -> PKPaymentRequestShippingMethodUpdate)?
    private var prepareTransactionCallback: ((_ transaction: inout Transaction) -> Void)?
    private var onCancelCallback: (() -> Void)?
    private var onDeclineCallback: ((_ reason: Error) -> Void)?
    private var shouldAuthorizeCallback: ((_ result: ApplePayResponse?) async -> AuthorizationDisposition)?

    @available(*, deprecated, message: "Use availability(supportedNetworks:) instead")
    public static func isAvailable() -> Bool {
        return PKPaymentAuthorizationViewController.canMakePayments()
    }

    /// Returns the three-state Apple Pay availability for the given supported card networks:
    /// `.unsupported` if the device can't do Apple Pay at all, `.unavailable` if it can but has
    /// no provisioned card on a supported network, `.available` otherwise.
    public static func availability(supportedNetworks: [Network]) -> ApplePayAvailability {
        return EvervaultPaymentView.availability(supportedNetworks: supportedNetworks)
    }

    public static func supportsDisbursements() -> Bool {
        if #available(iOS 17.0, *) {
            return PKPaymentAuthorizationViewController.supportsDisbursements()
        } else {
            return false
        }
    }

    // MARK: UIViewRepresentable

    public func makeUIView(context: Context) -> EvervaultPaymentView {
        // 1. Create the UIKit view
        let view = EvervaultPaymentView(
            appId: appUuid,
            appleMerchantId: appleMerchantIdentifier,
            transaction: transaction,
            supportedNetworks: supportedNetworks,
            buttonStyle: buttonStyle,
            buttonType: buttonType
        )
        // 2. Wire up our coordinator as its delegate
        view.delegate = context.coordinator
        return view
    }

    public func updateUIView(_ uiView: EvervaultPaymentView, context: Context) {
        // You could update merchantIdentifier/transaction here if you expose setters
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }


    // MARK: Coordinator

    public class Coordinator: NSObject, EvervaultPaymentViewDelegate, @unchecked Sendable {
        let parent: EvervaultPaymentViewRepresentable

        public init(parent: EvervaultPaymentViewRepresentable) {
            self.parent = parent
        }

        nonisolated public func evervaultPaymentView(_ view: EvervaultPaymentView, didAuthorizePayment result: ApplePayResponse?) {
            // hop back to main thread to update SwiftUI state
            DispatchQueue.main.async {
                self.parent.authorizedResponse = result
            }
        }

        @MainActor
        public func evervaultPaymentView(_ view: EvervaultPaymentView, shouldAuthorize result: ApplePayResponse?) async -> AuthorizationDisposition {
            return await self.parent.shouldAuthorizeCallback?(result) ?? .success(())
        }

        nonisolated public func evervaultPaymentView(_ view: EvervaultPaymentView, didFinishWithResult result: Result<Void, EvervaultError>) {
            DispatchQueue.main.async {
                self.parent.onResultCallback(result)
            }
        }

        nonisolated public func evervaultPaymentViewDidCancel(_ view: EvervaultPaymentView) {
            DispatchQueue.main.async {
                self.parent.onCancelCallback?()
            }
        }

        nonisolated public func evervaultPaymentView(_ view: EvervaultPaymentView, didDeclinePayment reason: Error) {
            DispatchQueue.main.async {
                self.parent.onDeclineCallback?(reason)
            }
        }

        nonisolated public func evervaultPaymentView(_ view: EvervaultPaymentView, didSelectShippingContact contact: PKContact) async -> PKPaymentRequestShippingContactUpdate? {
            if let handler = await self.parent.onShippingAddressChangeCallback {
                let updatedLineItems = handler(contact)
                return PKPaymentRequestShippingContactUpdate(
                    errors: nil,
                    paymentSummaryItems: updatedLineItems.map{ item in
                        PKPaymentSummaryItem(label: item.label, amount: item.amount.amount, type: item.type)
                    },
                    shippingMethods: await self.getShippingMethods(transaction: view.transaction)
                )
            }

            return nil
        }

        public func evervaultPaymentView(_ view: EvervaultPaymentView, didUpdatePaymentMethod paymentMethod: PKPaymentMethod) async -> PKPaymentRequestPaymentMethodUpdate? {
            if let handler = await self.parent.onPaymentMethodChangeCallback {
                return handler(paymentMethod)
            }

            return nil
        }

        public func evervaultPaymentView(_ view: EvervaultPaymentView, didChangeCouponCode couponCode: String) async -> PKPaymentRequestCouponCodeUpdate? {
            if let handler = await self.parent.onCouponCodeChangeCallback {
                return handler(couponCode)
            }

            return nil
        }

        public func evervaultPaymentView(_ view: EvervaultPaymentView, didSelectShippingMethod shippingMethod: PKShippingMethod) async -> PKPaymentRequestShippingMethodUpdate? {
            if let handler = await self.parent.onShippingMethodChangeCallback {
                return handler(shippingMethod)
            }

            return nil
        }

        public func evervaultPaymentView(_ view: EvervaultPaymentView, prepareTransaction transaction: inout Transaction) {
            if let handler = self.parent.prepareTransactionCallback {
                handler(&transaction)
            }
        }
        
        // Only `OneOffPaymentTransaction` models `shippingMethods`.
        // Recurring, disbursement, and automatic reload transactions have no defined semantics
        // for a selectable shipping surcharge, so they always return `[]`.
        private func getShippingMethods(transaction: Transaction) -> [PKShippingMethod] {
            switch transaction {
                case .oneOffPayment(let paymentRequest):
                    return paymentRequest.shippingMethods
                case .recurringPayment(_):
                    return []
                case .disbursement(_):
                    return []
                default:
                    // Covers .automaticReload, which can't be named directly here since it's
                    // gated to iOS 16+ while this switch compiles at the package's iOS 15 minimum.
                    return []
            }
        }
    }

    public func prepareTransaction(_ action: @escaping (inout Transaction) -> Void) -> EvervaultPaymentViewRepresentable {
        var copy = self
        copy.prepareTransactionCallback = action
        return copy
    }

    public func onShippingAddressChange(_ action: @escaping (PKContact) -> [SummaryItem]) -> EvervaultPaymentViewRepresentable {
        var copy = self
        copy.onShippingAddressChangeCallback = action
        return copy
    }

    public func onPaymentMethodChange(_ action: @escaping (PKPaymentMethod) -> PKPaymentRequestPaymentMethodUpdate) -> EvervaultPaymentViewRepresentable {
        var copy = self
        copy.onPaymentMethodChangeCallback = action
        return copy
    }

    /// Called when the buyer changes the coupon code on the Apple Pay sheet, shown only when `supportsCouponCode` is set on the transaction.
    public func onCouponCodeChange(_ action: @escaping (String) -> PKPaymentRequestCouponCodeUpdate) -> EvervaultPaymentViewRepresentable {
        var copy = self
        copy.onCouponCodeChangeCallback = action
        return copy
    }

    /// Called when the buyer selects a shipping method on the Apple Pay sheet.
    public func onShippingMethodChange(_ action: @escaping (PKShippingMethod) -> PKPaymentRequestShippingMethodUpdate) -> EvervaultPaymentViewRepresentable {
        var copy = self
        copy.onShippingMethodChangeCallback = action
        return copy
    }

    /// Called when the buyer dismisses the sheet without ever authorizing a payment, distinct from `onResult`'s success/failure.
    public func onCancel(_ action: @escaping () -> Void) -> EvervaultPaymentViewRepresentable {
        var copy = self
        copy.onCancelCallback = action
        return copy
    }

    /// Called when you reject an authorized payment by returning `.failure(reason)` from `shouldAuthorize`, distinct from `onResult`'s SDK-level success/failure.
    public func onDecline(_ action: @escaping (Error) -> Void) -> EvervaultPaymentViewRepresentable {
        var copy = self
        copy.onDeclineCallback = action
        return copy
    }

    /// Called after a payment is authorized, letting you return `.success` or `.failure` to accept or reject it before the sheet reports success.
    public func shouldAuthorize(_ action: @escaping (ApplePayResponse?) async -> AuthorizationDisposition) -> EvervaultPaymentViewRepresentable {
        var copy = self
        copy.shouldAuthorizeCallback = action
        return copy
    }
}
