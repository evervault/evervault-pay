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
