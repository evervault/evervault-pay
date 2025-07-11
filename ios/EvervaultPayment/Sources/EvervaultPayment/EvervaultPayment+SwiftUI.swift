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
        onFinish: @escaping () -> Void,
        onError: @escaping (_ error: Error?) -> Void
    ) {
        self.appUuid = appId
        self.appleMerchantIdentifier = appleMerchantId
        self.transaction = transaction
        self.supportedNetworks = supportedNetworks
        self.buttonStyle = buttonStyle
        self.buttonType = buttonType

        self._authorizedResponse = authorizedResponse
        self.onFinish = onFinish
        self.onError = onError
    }
  
    /// Called when Apple Pay authorizes the payment
    @Binding var authorizedResponse: ApplePayResponse?

    /// Called when the sheet is dismissed
    public var onFinish: () -> Void
    
    public var onError: (_ error: Error?) -> Void
    
    public static func isAvailable() -> Bool {
        return PKPaymentAuthorizationViewController.canMakePayments()
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

        nonisolated public func evervaultPaymentView(
            _ view: EvervaultPaymentView,
            didAuthorizePayment result: ApplePayResponse?
        ) {
          // hop back to main thread to update SwiftUI state
            let parent = self.parent
            DispatchQueue.main.async {
                parent.authorizedResponse = result
            }
        }

        nonisolated public func evervaultPaymentView(
            _ view: EvervaultPaymentView,
            didFinishWithResult result: String?
        ) {
            let parent = self.parent
            DispatchQueue.main.async {
                parent.onFinish()
            }
        }
        
        nonisolated public func evervaultPaymentView(
            _ view: EvervaultPaymentView,
            didFinishWithError error: Error?
        ) {
            let parent = self.parent
            DispatchQueue.main.async {
                parent.onError(error)
            }
        }
    }
}
