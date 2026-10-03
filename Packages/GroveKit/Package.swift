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
]

let package = Package(
  name: "GroveKit",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    .library(name: "GroveKit", targets: ["GroveKit"]),
  ],
  targets: [
    .target(name: "GroveKit", swiftSettings: swiftSettings),
    .testTarget(name: "GroveKitTests", dependencies: ["GroveKit"], swiftSettings: swiftSettings),
  ],
  swiftLanguageModes: [.v5]
)
