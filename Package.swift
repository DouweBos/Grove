// swift-tools-version: 6.2
// Exposes GroveKit to other apps, which depend on this repository by URL. Grove itself uses
// Packages/GroveKit as a local package; keep the targets and settings here in step with its manifest.
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
  ],
  swiftLanguageModes: [.v5]
)
