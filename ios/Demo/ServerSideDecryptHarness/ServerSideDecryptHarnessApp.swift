//
//  ServerSideDecryptHarnessApp.swift
//  ServerSideDecryptHarness
//
//  Test harness for server-side Apple Pay decryption.
//  Doesn't use the EvervaultPayment SDK on purpose: it plays the part of a merchant's server
//  that receives an Apple Pay token without any Evervault SDK involved.
//

import SwiftUI

@main
struct ServerSideDecryptHarnessApp: App {
    var body: some Scene {
        WindowGroup {
            ServerSideDecryptView()
        }
    }
}
