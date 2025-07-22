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
        prepareTransaction: ((_ transaction: inout Transaction) -> Void)? = nil,
        onShippingAddressChange: ((_ shippingMethod: PKShippingMethod) -> PKPaymentRequestShippingMethodUpdate)? = nil,
        onPaymentMethodChange: ((_ paymentMethod: PKPaymentMethod) -> PKPaymentRequestPaymentMethodUpdate)? = nil,
        onResult: @escaping (_ result: Result<(), EvervaultError>) -> Void
    ) {
        self.appUuid = appId
        self.appleMerchantIdentifier = appleMerchantId
        self.transaction = transaction
        self.supportedNetworks = supportedNetworks
        self.buttonStyle = buttonStyle
        self.buttonType = buttonType

        self._authorizedResponse = authorizedResponse
        self.onResult = onResult
        self.prepareTransaction = prepareTransaction
        self.onShippingAddressChange = onShippingAddressChange
        self.onPaymentMethodChange = onPaymentMethodChange
    }

    /// Called when Apple Pay authorizes the payment
    @Binding var authorizedResponse: ApplePayResponse?

    /// Called when the sheet is dismissed
    public var onResult: (_ result: Result<(), EvervaultError>) -> Void

    public var onShippingAddressChange: ((_ shippingMethod: PKShippingMethod) -> PKPaymentRequestShippingMethodUpdate)?
    public var onPaymentMethodChange: ((_ paymentMethod: PKPaymentMethod) -> PKPaymentRequestPaymentMethodUpdate)?

    public var prepareTransaction: ((_ transaction: inout Transaction) -> Void)?

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
                self.parent.onResult(result)
            }
        }

        public func evervaultPaymentView(_ view: EvervaultPaymentView, didUpdateShippingMethod shippingMethod: PKShippingMethod) async -> PKPaymentRequestShippingMethodUpdate? {
            if let handler = self.parent.onShippingAddressChange {
                return await handler(shippingMethod)
            }

            return nil
        }

        public func evervaultPaymentView(_ view: EvervaultPaymentView, didUpdatePaymentMethod paymentMethod: PKPaymentMethod) async -> PKPaymentRequestPaymentMethodUpdate? {
            if let handler = self.parent.onPaymentMethodChange {
                return await handler(paymentMethod)
            }

            return nil
        }

        public func evervaultPaymentView(_ view: EvervaultPaymentView, prepareTransaction transaction: inout Transaction) {
            if let handler = self.parent.prepareTransaction {
                handler(&transaction)
            }
        }
    }
}
