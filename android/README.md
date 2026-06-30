# Building the demo app

Create a new file `local.properties`:

```
EVERVAULT_APP_ID=<YOUR_EVERVAULT_APP_ID>
EVERVAULT_MERCHANT_ID=<YOUR_EVERVAULT_MERCHANT_ID>
```

```bash
./gradlew build
```

## Releasing a new version

1. Bump the version in the `googlepay/build.gradle.kts` file
2. Create a new release in the GitHub repository with the tag `android-v<VERSION>`
