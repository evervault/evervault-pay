# Building the demo app

Create a new file `local.properties`:

```
EVERVAULT_APP_ID=<YOUR_EVERVAULT_APP_ID>
EVERVAULT_MERCHANT_ID=<YOUR_EVERVAULT_MERCHANT_ID>
```

```bash
./gradlew build
```

## Inline Google Pay authorization

Use inline authorization when your app must accept or reject a payment before
Google Pay closes its sheet. Configure a handler with a public no-argument
constructor. Google Pay creates the handler in a service, so it must not retain
an `Activity`, `ViewModel`, or composable.

```kotlin
class CheckoutAuthorizationHandler : GooglePayAuthorizationHandler {
    override suspend fun authorize(
        payment: TokenResponse,
        transaction: Transaction,
    ): GooglePayAuthorizationResult {
        return try {
            checkoutApi.charge(payment, transaction)
            GooglePayAuthorizationResult.Accept
        } catch (_: CardDeclined) {
            GooglePayAuthorizationResult.Reject(
                message = "Your card was declined. Try another card.",
                reason = "PAYMENT_DATA_INVALID",
            )
        }
    }
}

val config = Config(
    appId = "app_123",
    merchantId = "merchant_123",
    googlePayAuthorization = GooglePayAuthorizationConfig(
        CheckoutAuthorizationHandler::class.java,
    ),
)
```

`Accept` completes Google Pay. `Reject` returns an inline error and keeps the
sheet open so the buyer can retry or choose another card. After acceptance, the
view model emits `PaymentState.PaymentAuthorized`. Without this configuration,
the existing `PaymentState.PaymentCompleted` flow remains unchanged.

## Releasing a new version

1. Bump the version in the `googlepay/build.gradle.kts` file (could be done in the same PR as your change, or as its own separate version-bump PR — there's no technical requirement either way; a separate PR just lets you batch several merged changes into one release instead of releasing on every merge)
2. Merge that change to `main`
3. Create a new release in the GitHub repository with the tag `android-v<VERSION>` (e.g. `android-v0.0.31`) — the `android-` prefix is required, not just a naming convention: [`jitpack.yml`](../jitpack.yml) explicitly refuses to build any tag that doesn't start with `android-`, and the iOS [Cocoapods workflow](../.github/workflows/cocoapods-deploy.yml) triggers on *any* pushed tag except ones prefixed `android-`. Getting the prefix wrong means Android consumers can't resolve the release **and** risks accidentally kicking off an unrelated iOS publish attempt.
