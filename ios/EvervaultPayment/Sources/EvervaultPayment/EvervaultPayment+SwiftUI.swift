//
//  EvervaultPayment+SwiftUI.swift
//  EvervaultPayment
//
//  Created by Jake Grogan on 12/06/2025.
//

import SwiftUI
import PassKit

/// A SwiftUI‐friendly wrapper around your UIKit EvervaultPaymentView.
public struct EvervaultPaymentViewRepresentable: UIViewRepresentable {
  
    // MARK: Inputs
    let merchantIdentifier: String
    let transaction: Transaction
    let supportedNetworks: [Network]
    
    public init(
        merchantIdentifier: String,
        transaction: Transaction,
        supportedNetworks: [Network],
        authorizedResponse: Binding<ApplePayResponse?>,
        onFinish: @escaping () -> Void
    ) {
        self.merchantIdentifier = merchantIdentifier
        self.transaction = transaction
        self.supportedNetworks = supportedNetworks
        self._authorizedResponse = authorizedResponse
        self.onFinish = onFinish
    }
  
    /// Called when Apple Pay authorizes the payment
    @Binding var authorizedResponse: ApplePayResponse?

    /// Called when the sheet is dismissed
    public var onFinish: () -> Void
  
  
    // MARK: UIViewRepresentable
  
    public func makeUIView(context: Context) -> EvervaultPaymentView {
        // 1. Create the UIKit view
        let view = EvervaultPaymentView(
            merchantIdentifier: merchantIdentifier,
            transaction: transaction,
            supportedNetworks: supportedNetworks
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
    }
}
