import XCTest
import SwiftUI
import PassKit
@testable import EvervaultPayment

@MainActor
final class EvervaultPaymentViewRepresentableUpdateUIViewTests: XCTestCase {

    private final class Model: ObservableObject {
        @Published var transaction: EvervaultPayment.Transaction
        init(_ transaction: EvervaultPayment.Transaction) {
            self.transaction = transaction
        }
    }

    private struct Harness: View {
        @ObservedObject var model: Model
        @State private var authorizedResponse: ApplePayResponse? = nil

        var body: some View {
            EvervaultPaymentViewRepresentable(
                appId: "app_test",
                appleMerchantId: "merchant.test",
                transaction: model.transaction,
                supportedNetworks: [.visa],
                authorizedResponse: $authorizedResponse,
                onResult: { _ in }
            )
        }
    }

    private func findEvervaultPaymentView(in view: UIView) -> EvervaultPaymentView? {
        if let match = view as? EvervaultPaymentView {
            return match
        }
        for subview in view.subviews {
            if let found = findEvervaultPaymentView(in: subview) {
                return found
            }
        }
        return nil
    }

    private func totalAmount(_ transaction: EvervaultPayment.Transaction) -> NSDecimalNumber? {
        guard case let .oneOffPayment(oneOff) = transaction else { return nil }
        return oneOff.paymentSummaryItems.first?.amount.amount
    }

    private func makeTransaction(total: String) throws -> EvervaultPayment.Transaction {
        .oneOffPayment(try OneOffPaymentTransaction(
            country: "US",
            currency: "USD",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount(total))]
        ))
    }

    func testUpdateUIViewPropagatesNewTransactionToTheLiveView() throws {
        let model = Model(try makeTransaction(total: "10.00"))

        let hostingController = UIHostingController(rootView: Harness(model: model))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.layoutIfNeeded()

        guard let paymentView = findEvervaultPaymentView(in: hostingController.view) else {
            XCTFail("Could not locate EvervaultPaymentView in the hosted hierarchy")
            return
        }
        XCTAssertEqual(totalAmount(paymentView.transaction), NSDecimalNumber(string: "10.00"))

        // Simulate the SwiftUI view re-rendering with a changed transaction (e.g. cart total changed).
        model.transaction = try makeTransaction(total: "25.00")
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        hostingController.view.layoutIfNeeded()

        XCTAssertEqual(
            totalAmount(paymentView.transaction),
            NSDecimalNumber(string: "25.00"),
            "updateUIView should push the new transaction from the SwiftUI struct into the underlying EvervaultPaymentView"
        )
    }
}

@MainActor
final class EvervaultPaymentViewRepresentableShippingContactUpdateTests: XCTestCase {

    private func makeRepresentable(transaction: EvervaultPayment.Transaction) -> EvervaultPaymentViewRepresentable {
        EvervaultPaymentViewRepresentable(
            appId: "app_test",
            appleMerchantId: "merchant.test",
            transaction: transaction,
            supportedNetworks: [.visa],
            authorizedResponse: .constant(nil),
            onResult: { _ in }
        )
    }

    private func makeView(transaction: EvervaultPayment.Transaction) -> EvervaultPaymentView {
        EvervaultPaymentView(
            appId: "app_test",
            appleMerchantId: "merchant.test",
            transaction: transaction,
            supportedNetworks: [.visa],
            buttonStyle: .automatic,
            buttonType: .buy
        )
    }

    private func makeTransaction(total: String) throws -> EvervaultPayment.Transaction {
        .oneOffPayment(try OneOffPaymentTransaction(
            country: "US",
            currency: "USD",
            paymentSummaryItems: [SummaryItem(label: "Total", amount: Amount(total))]
        ))
    }

    func testNewCallbackIsForwardedUnmodifiedWhenOnlyItIsRegistered() async throws {
        let transaction = try makeTransaction(total: "10.00")
        let expectedUpdate = PKPaymentRequestShippingContactUpdate(
            errors: nil,
            paymentSummaryItems: [PKPaymentSummaryItem(label: "New Handler Total", amount: NSDecimalNumber(string: "42.00"))],
            shippingMethods: []
        )
        let representable = makeRepresentable(transaction: transaction)
            .onShippingAddressChange { _ in expectedUpdate }
        let coordinator = representable.makeCoordinator()

        let result = await coordinator.evervaultPaymentView(makeView(transaction: transaction), didSelectShippingContact: PKContact())

        XCTAssertTrue(result === expectedUpdate, "the new callback's return value should be forwarded unmodified")
    }

    func testOldCallbackConvertsSummaryItemsWhenOnlyItIsRegistered() async throws {
        let transaction = try makeTransaction(total: "10.00")
        let representable = makeRepresentable(transaction: transaction)
            .onShippingAddressChange { _ in [SummaryItem(label: "Old Handler Total", amount: Amount("12.00"))] }
        let coordinator = representable.makeCoordinator()

        let result = await coordinator.evervaultPaymentView(makeView(transaction: transaction), didSelectShippingContact: PKContact())

        XCTAssertEqual(result?.paymentSummaryItems.first?.label, "Old Handler Total")
        XCTAssertEqual(result?.paymentSummaryItems.first?.amount, NSDecimalNumber(string: "12.00"))
    }

    func testNewCallbackTakesPriorityWhenBothAreRegistered() async throws {
        let transaction = try makeTransaction(total: "10.00")
        let expectedUpdate = PKPaymentRequestShippingContactUpdate(
            errors: nil,
            paymentSummaryItems: [PKPaymentSummaryItem(label: "New Handler Total", amount: NSDecimalNumber(string: "42.00"))],
            shippingMethods: []
        )
        let representable = makeRepresentable(transaction: transaction)
            .onShippingAddressChange { _ in [SummaryItem(label: "Old Handler Total", amount: Amount("12.00"))] }
            .onShippingAddressChange { _ in expectedUpdate }
        let coordinator = representable.makeCoordinator()

        let result = await coordinator.evervaultPaymentView(makeView(transaction: transaction), didSelectShippingContact: PKContact())

        XCTAssertTrue(result === expectedUpdate, "the new callback should take priority when both are registered")
    }
}
