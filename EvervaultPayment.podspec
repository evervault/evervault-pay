Pod::Spec.new do |s|
  s.name             = "EvervaultPayment"
  s.version          = "0.0.6"                          # ← bump this per release
  s.summary          = "Client library for Evervault mobile payments"
  s.homepage         = "https://github.com/evervault/evervault-pay"
  s.license          = { :type => "MIT", :file => "LICENSE" }
  s.author           = { "Evervault Engineering" => "engineering@evervault.com" }
  s.platform         = :ios, "12.0"
  s.swift_version    = "6.1"

  # point at the git tag; make sure it matches s.version
  s.source = {
    :git  => "https://github.com/evervault/evervault-pay.git",
    :tag  => "ios-v#{s.version}"
  }

  # include only the Swift package sources under ios/EvervaultPayment
  s.source_files = "ios/EvervaultPayment/**/*.{swift}"

  # exclude test files
  s.exclude_files = [
    "ios/EvervaultPayment/Tests/**/*",
    "ios/EvervaultPayment/Package.swift"
  ]

  # link against the built-in Apple Pay framework
  s.frameworks = "Foundation", "PassKit"

  # if the package has any resource bundles, assets, etc, add:
  # not required for now but leaving here in case
  # s.resources    = "ios/EvervaultPayment/Resources/**/*"
end
