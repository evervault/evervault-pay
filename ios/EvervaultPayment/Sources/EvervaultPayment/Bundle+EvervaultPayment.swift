//
//  Bundle+EvervaultPayment.swift
//  EvervaultPayment
//
//  Created by Jake Grogan on 04/07/2025.
//

import Foundation

private let defaultBaseUrl = "https://api.evervault.com"

public extension Bundle {
  var evervaultBaseURL: URL {
    if let s = object(forInfoDictionaryKey: "EvervaultBaseURL") as? String,
       let u = URL(string: s) { return u }
    return URL(string: defaultBaseUrl)!
  }
}
