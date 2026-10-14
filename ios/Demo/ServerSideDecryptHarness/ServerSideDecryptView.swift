//
//  ServerSideDecryptView.swift
//  ServerSideDecryptHarness
//
//  Test harness for server-side Apple Pay decryption.
//  Makes a real Apple Pay payment in the app and sends the encrypted token to
//  `POST /payments/apple-pay/decrypt` (see `ServerSideDecryptApi`), like a merchant's server would.
//  Apple encrypts the token the same way no matter how the merchant receives it,
//  so this tests the real decryption end to end.
//
//  Needs a physical iPhone: the Simulator doesn't produce a real encrypted token.
//

import SwiftUI
import PassKit
import CryptoKit

private let supportedNetworks: [PKPaymentNetwork] = [.visa, .masterCard, .amex]

/// Shows the Apple Pay sheet, handles its callbacks, and keeps the result for the view to display.
@MainActor
final class ServerSideDecryptModel: NSObject, ObservableObject {
    enum Outcome {
        case success(String)
        case failure(String)
        case cancelled
    }

    @Published private(set) var isRunning = false
    @Published private(set) var outcome: Outcome? = nil

    private var controller: PKPaymentAuthorizationController?
    private var api: ServerSideDecryptApi?
    private var pendingOutcome: Outcome?
    private var expectedApplicationDataHash: String?

    func pay(config: ServerSideDecryptConfig, includeApplicationData: Bool) {
        let request = PKPaymentRequest()
        request.merchantIdentifier = config.merchantId
        request.countryCode = "IE"
        request.currencyCode = "EUR"
        request.supportedNetworks = supportedNetworks
        request.merchantCapabilities = .threeDSecure
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(label: "Test Item", amount: NSDecimalNumber(string: "1.00")),
            PKPaymentSummaryItem(label: "Evervault Demo", amount: NSDecimalNumber(string: "1.00")),
        ]
        // Apple puts a SHA-256 hash of this in the token header and includes it in the signature.
        // Apple Messages for Business tokens have it, so test both with and without.
        let applicationData = includeApplicationData ? Data("evervault-harness-\(UUID().uuidString)".utf8) : nil
        request.applicationData = applicationData
        expectedApplicationDataHash = applicationData.map { hexSHA256($0) }

        let api = ServerSideDecryptApi(config: config)
        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self
        self.controller = controller
        self.api = api
        outcome = nil
        isRunning = true

        controller.present { [weak self] presented in
            guard !presented else { return }
            Task { @MainActor in
                self?.finish(.failure("Couldn't present the Apple Pay sheet. Check that \(ServerSideDecryptConfig.merchantIdKey) matches a merchant ID in the entitlements file, and that a card is provisioned in Wallet."))
            }
        }
    }

    private func finish(_ outcome: Outcome) {
        self.outcome = outcome
        isRunning = false
        controller = nil
        api = nil
        pendingOutcome = nil
        expectedApplicationDataHash = nil
    }

    /// Says whether the token had `applicationData`, and whether it's the hash of what the request sent.
    fileprivate func applicationDataSummary(tokenHash: String?) -> String {
        switch (expectedApplicationDataHash, tokenHash) {
        case (nil, nil):
            return "applicationData: not set, not in token"
        case let (expected?, actual?):
            let matches = expected.caseInsensitiveCompare(actual) == .orderedSame
            return "applicationData: in token, \(matches ? "matches" : "DOESN'T match") request hash\n\(actual)"
        case (_?, nil):
            return "applicationData: set on request but MISSING from token"
        case let (nil, actual?):
            return "applicationData: not set, but token has one\n\(actual)"
        }
    }
}

private func hexSHA256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

extension ServerSideDecryptModel: PKPaymentAuthorizationControllerDelegate {
    nonisolated func paymentAuthorizationController(
        _ controller: PKPaymentAuthorizationController,
        didAuthorizePayment payment: PKPayment,
        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
    ) {
        Task { @MainActor in
            guard let api = self.api else {
                completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
                return
            }
            do {
                let result = try await api.decrypt(payment.token)
                let summary = self.applicationDataSummary(tokenHash: result.applicationDataHash)
                self.pendingOutcome = .success("\(summary)\n\n\(result.body)")
                completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
            } catch {
                let mode = self.expectedApplicationDataHash == nil ? "not set" : "set on request"
                self.pendingOutcome = .failure("applicationData: \(mode)\n\n\(error.localizedDescription)")
                completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
            }
        }
    }

    nonisolated func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        Task { @MainActor in
            await controller.dismiss()
            self.finish(self.pendingOutcome ?? .cancelled)
        }
    }
}

struct ServerSideDecryptView: View {
    @StateObject private var model = ServerSideDecryptModel()
    @State private var includeApplicationData = false
    private let config = ServerSideDecryptConfig.load()

    var body: some View {
        VStack(spacing: 20) {
            Text("Server-Side Decrypt")
            Text("Forwards the raw Apple Pay token to POST /payments/apple-pay/decrypt with an app ID and API key, as a merchant's own server would.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            switch config {
            case let .failure(missing):
                Text("Set these environment variables on the ServerSideDecryptHarness scheme, then run the app from Xcode:\n\(missing.variables.joined(separator: "\n"))")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            case let .success(config):
                Text(config.baseUrl)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
                Toggle("Include applicationData", isOn: $includeApplicationData)
                    .font(.footnote)
                    .disabled(model.isRunning)
                payButton(config: config)
            }

            resultView
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func payButton(config: ServerSideDecryptConfig) -> some View {
#if targetEnvironment(simulator)
        Text("Run on a physical iPhone - the Simulator doesn't produce a real encrypted token.")
            .font(.footnote)
            .foregroundStyle(.orange)
            .multilineTextAlignment(.center)
#else
        if PKPaymentAuthorizationController.canMakePayments(usingNetworks: supportedNetworks) {
            PayWithApplePayButton(.checkout) {
                model.pay(config: config, includeApplicationData: includeApplicationData)
            }
            .frame(height: 45)
            .disabled(model.isRunning)
        } else {
            Text("No supported card in Wallet. Add a sandbox test card while signed in as a sandbox tester.")
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
#endif
    }

    @ViewBuilder
    private var resultView: some View {
        if model.isRunning {
            ProgressView()
        }
        switch model.outcome {
        case let .success(body):
            resultText(title: "Decrypted", body: body, color: .green)
        case let .failure(message):
            resultText(title: "Failed", body: message, color: .red)
        case .cancelled:
            Text("Sheet dismissed without authorizing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case nil:
            EmptyView()
        }
    }

    private func resultText(title: String, body: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).foregroundStyle(color)
            ScrollView {
                Text(body)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

#Preview {
    ServerSideDecryptView()
}
