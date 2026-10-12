## Building the Demo app locally

`Demo/Demo.entitlements` isn't committed (`**/*.entitlements` is gitignored — it holds your own Apple Pay merchant ID, which is tied to your Apple Developer account). Both the Debug and Release configs point at this single file, so create it yourself before building:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.in-app-payments</key>
	<array>
		<string>merchant.your.bundle.id</string>
	</array>
</dict>
</plist>
```

## ServerSideDecryptHarness

`Demo.xcodeproj` has a second app target, **ServerSideDecryptHarness** ([`Demo/ServerSideDecryptHarness`](Demo/ServerSideDecryptHarness)). It takes a real Apple Pay payment and forwards the encrypted `PKPaymentToken.paymentData` straight to `POST /payments/apple-pay/decrypt` with an app ID and API key (Basic auth) — standing in for a merchant's own server receiving a token outside any Evervault SDK (e.g. Apple Messages for Business). It deliberately doesn't link `EvervaultPayment`, and isn't part of the published package.

It signs with the same `Demo/Demo.entitlements` as the Demo app, under its own bundle ID (`com.evervault.testios.ServerSideDecryptHarness`).

Set these on the **ServerSideDecryptHarness** scheme (Edit Scheme → Run → Arguments → Environment Variables). `xcshareddata` is gitignored, so they stay local. Xcode only passes these variables when it launches the app, so always run it from Xcode — opening it from the home screen will just show which variables are missing:

| Variable                          | Value                                                                                                            |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `SERVER_SIDE_DECRYPT_APP_ID`      | The ID of the Evervault app the API key belongs to (`app_...`)                                                   |
| `SERVER_SIDE_DECRYPT_API_KEY`     | An API key with the `applePay:decrypt` grant, on an app with the `apple_pay_server_side_decryption` flag enabled |
| `SERVER_SIDE_DECRYPT_MERCHANT_ID` | The merchant ID from your `Demo.entitlements`, whose Evervault app has the payment-processing certificate        |
| `SERVER_SIDE_DECRYPT_BASE_URL`    | Optional. API host to call; defaults to `https://api.evervault.com`                 |

Run it on a physical iPhone with a sandbox tester signed in and a sandbox test card in Wallet — the Simulator can't produce a real encrypted token. The decrypted response (or the HTTP status and error body) is shown on screen.

## Releasing a new version

1. Bump `spec.version` in [`EvervaultPayment.podspec`](../EvervaultPayment.podspec) (could be done in the same PR as your change, or as its own separate version-bump PR — there's no technical requirement either way; a separate PR just lets you batch several merged changes into one release instead of releasing on every merge)
2. Merge that change to `main`
3. Push a tag matching the new version **exactly** (e.g. `0.0.25` — not `v0.0.25`, not `ios-v0.0.25`) on the commit on `main` that has the version bump:
   ```bash
   git checkout main
   git pull
   git tag 0.0.25
   git push origin 0.0.25
   ```
   This triggers the [Cocoapods workflow](../.github/workflows/cocoapods-deploy.yml) to publish to CocoaPods trunk, and is also what Swift Package Manager resolves versions against directly (no separate SPM publish step is needed). The exact naming matters: this repo also has `android-v*` and legacy `ios-v*` tags for other purposes — neither CocoaPods nor SPM will recognize those formats, so a wrongly-named tag looks like a successful push but silently releases nothing.
