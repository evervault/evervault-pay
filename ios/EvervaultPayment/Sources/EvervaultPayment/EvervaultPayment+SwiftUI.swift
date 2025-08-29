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
    private var prepareTransactionCallback: ((_ transaction: inout Transaction) -> Void)?

    public static func isAvailable() -> Bool {
        return PKPaymentAuthorizationViewController.canMakePayments()
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

    public class Coordinator: NSObject, EvervaultPaymentViewDelegate {
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

        nonisolated public func evervaultPaymentView(_ view: EvervaultPaymentView, didFinishWithResult result: Result<Void, EvervaultError>) {
            DispatchQueue.main.async {
                self.parent.onResultCallback(result)
            }
        }

        nonisolated public func evervaultPaymentView(_ view: EvervaultPaymentView, didSelectShippingContact contact: PKContact) async -> PKPaymentRequestShippingContactUpdate? {
            if let handler = await self.parent.onShippingAddressChangeCallback {
                let updatedLineItems = handler(contact)
                return PKPaymentRequestShippingContactUpdate(
                    errors: nil,
                    paymentSummaryItems: updatedLineItems.map{ item in
                        PKPaymentSummaryItem(label: item.label, amount: item.amount.amount)
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

        public func evervaultPaymentView(_ view: EvervaultPaymentView, prepareTransaction transaction: inout Transaction) {
            if let handler = self.parent.prepareTransactionCallback {
                handler(&transaction)
            }
        }
        
        // Helper function to get the shipping methods for the various transaction types
        private func getShippingMethods(transaction: Transaction) -> [PKShippingMethod] {
            switch transaction {
                case .oneOffPayment(let paymentRequest):
                    return paymentRequest.shippingMethods
                case .recurringPayment(_):
                    return []
                case .disbursement(_):
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
}
