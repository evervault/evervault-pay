Pod::Spec.new do |spec|
  spec.name         = "EvervaultPayment"
  spec.version      = "1.0.0"
  spec.summary      = "Evervault Pay SDK for iOS - Secure Apple Pay integration with Evervault encryption"
  spec.description  = <<-DESC
    The Evervault Pay SDK for iOS provides a secure way to integrate Apple Pay into your iOS applications.
    It handles the complete payment flow including token encryption and decryption through Evervault's
    secure infrastructure, supporting one-off payments, recurring payments, and disbursements.
  DESC
  
  spec.homepage     = "https://evervault.com"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Evervault" => "support@evervault.com" }
  spec.platform     = :ios, '15.0'
  spec.source       = { :git => "https://github.com/evervault/evervault-pay.git", :tag => "#{spec.version}" }
  
  spec.source_files = "ios/EvervaultPayment/Sources/EvervaultPayment/**/*.swift"
  spec.swift_version = "5.7"
  
  spec.frameworks   = "PassKit", "Foundation", "UIKit"
  
  spec.documentation_url = "https://docs.evervault.com/sdks/ios"
  
  spec.social_media_url = "https://twitter.com/evervault"
  
  # Ensure the pod works with both static and dynamic linking
  spec.static_framework = false
  
  # Add any test files if they exist
  # spec.test_spec 'Tests' do |test_spec|
  #   test_spec.source_files = 'Tests/**/*.swift'
  # end
end
