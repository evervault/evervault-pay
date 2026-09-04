# Building the demo app

Create a new file `local.properties`:

```
EVERVAULT_APP_ID=<YOUR_EVERVAULT_APP_ID>
EVERVAULT_MERCHANT_ID=<YOUR_EVERVAULT_MERCHANT_ID>
```

The sample app uses the existing Google Pay flow by default. To test inline
merchant authorization, add these optional properties:

```
ENABLE_GOOGLE_PAY_AUTHORIZATION=true
GOOGLE_PAY_AUTHORIZATION_RESULT=accept
```

Set `GOOGLE_PAY_AUTHORIZATION_RESULT` to `reject` to show an inline rejection.
The sample handler uses a fixed result for demonstration only. A production
handler must ask the merchant backend whether to accept the payment.

To test shipping address collection, shipping option selection, and dynamic
total recompute, add this optional property:

```
ENABLE_GOOGLE_PAY_SHIPPING=true
```

The shipping option list itself is fixed - a handler can only accept the
current selection (with a recomputed total) or reject it, not add, remove,
or reprice options in the list shown to the buyer. Google Pay also has no
price field of its own for a shipping option, so labels are shown exactly as
given; bake a price in yourself if you want one shown, e.g. "Express: £9.99".

The sample offers a fixed "Standard"/"Express" list. Standard is priced by
destination (free normally, a flat 14.95 for Hong Kong/Japan, unavailable
for Brazil/Canada), so its label is left bare rather than show a price that
would go stale; Express is a flat rate everywhere, so its label bakes the
price in. The result screen prints the returned `shippingAddress` and
`shippingOption`.

```bash
./gradlew build
```

## Releasing a new version

1. Bump the version in the `googlepay/build.gradle.kts` file (could be done in the same PR as your change, or as its own separate version-bump PR — there's no technical requirement either way; a separate PR just lets you batch several merged changes into one release instead of releasing on every merge)
2. Merge that change to `main`
3. Create a new release in the GitHub repository with the tag `android-v<VERSION>` (e.g. `android-v0.0.31`) — the `android-` prefix is required, not just a naming convention: [`jitpack.yml`](../jitpack.yml) explicitly refuses to build any tag that doesn't start with `android-`, and the iOS [Cocoapods workflow](../.github/workflows/cocoapods-deploy.yml) triggers on *any* pushed tag except ones prefixed `android-`. Getting the prefix wrong means Android consumers can't resolve the release **and** risks accidentally kicking off an unrelated iOS publish attempt.
