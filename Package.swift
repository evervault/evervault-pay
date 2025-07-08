import PackageDescription

let package = Package(
  name: "evervault-pay",
  platforms: [
    .iOS(.v15)
  ],
  products: [
    .library(
      name: "EvervaultPayment",
      targets: ["EvervaultPayment"]
    ),
  ],
  dependencies: [],
  targets: [
    .target(
      name: "EvervaultPayment",
      path: "ios/EvervaultPayment"
    )
  ]
)