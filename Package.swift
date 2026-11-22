// swift-tools-version: 6.2
// Exposes GroveKit and GroveUIKit to other apps, which depend on this repository by URL. Grove itself uses
// Packages/* as local packages; keep the targets and settings here in step with their manifests.
import PackageDescription

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
  name: "Grove",
  platforms: [.macOS(.v15), .iOS(.v18)],
  products: [
    .library(name: "GroveKit", targets: ["GroveKit"]),
    .library(name: "GroveUIKit", targets: ["GroveUIKit"]),
  ],
  targets: [
    .target(
      name: "GroveKit",
      path: "Packages/GroveKit/Sources/GroveKit",
      resources: [.process("Resources")],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "GroveKitTests",
      dependencies: ["GroveKit"],
      path: "Packages/GroveKit/Tests/GroveKitTests",
      swiftSettings: swiftSettings
    ),
    .target(
      name: "GroveUIKit",
      dependencies: ["GroveKit"],
      path: "Packages/GroveUIKit/Sources/GroveUIKit",
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "GroveUIKitTests",
      dependencies: ["GroveKit", "GroveUIKit"],
      path: "Packages/GroveUIKit/Tests/GroveUIKitTests",
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "GroveUIKitConsumerTests",
      dependencies: ["GroveKit", "GroveUIKit"],
      path: "Packages/GroveUIKit/Tests/GroveUIKitConsumerTests",
      // As an importing app builds: Swift 6, without Grove's default isolation.
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ],
  swiftLanguageModes: [.v5]
)
