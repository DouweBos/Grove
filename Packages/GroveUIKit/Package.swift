// swift-tools-version: 6.2
import PackageDescription

// Mirrors Grove's build settings so moved code keeps its isolation and semantics.
let swiftSettings: [SwiftSetting] = [
  .defaultIsolation(MainActor.self),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("InferSendableFromCaptures"),
  .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
  .enableUpcomingFeature("DisableOutwardActorInference"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .swiftLanguageMode(.v5),
]

let package = Package(
  name: "GroveUIKit",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    .library(name: "GroveUIKit", targets: ["GroveUIKit"]),
  ],
  dependencies: [.package(path: "../GroveKit")],
  targets: [
    .target(name: "GroveUIKit", dependencies: [.product(name: "GroveKit", package: "GroveKit")], swiftSettings: swiftSettings),
    .testTarget(
      name: "GroveUIKitTests",
      dependencies: ["GroveUIKit", .product(name: "GroveKit", package: "GroveKit")],
      swiftSettings: swiftSettings),
    .testTarget(
      name: "GroveUIKitConsumerTests",
      dependencies: ["GroveUIKit", .product(name: "GroveKit", package: "GroveKit")],
      swiftSettings: [.swiftLanguageMode(.v6)]),
  ]
)
