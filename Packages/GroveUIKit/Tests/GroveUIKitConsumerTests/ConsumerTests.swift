// ConsumerTests.swift
// GroveUIKitConsumerTests
//
// Built in Swift 6 without Grove's default isolation, as an importing app is.

#if os(macOS)
import GroveKit
import GroveUIKit
import SwiftUI
import Testing

@MainActor
private struct HostCommands: GitCommandPerforming {
    let features: GitFeatures

    func perform(_ command: GitCommand, progress: (@Sendable (Double) -> Void)?) async throws {
        try requireSupport(for: command)
    }
}

@MainActor
struct ConsumerTests {

    @Test func anAppCanStyleAndLimitTheKit() {
        var style = GitUIStyle.system
        style.fontScale = 1.25
        style.showsPointingHand = true
        var features = GitFeatures.all
        features.remove([.merge], reason: "Only in the project root")
        let view = GitBanner(symbol: "xmark.octagon", message: "Push rejected.", tone: .negative)
            .gitUIStyle(style)
            .gitFeatures(features)
        #expect(NSHostingController(rootView: view).sizeThatFits(in: NSSize(width: 400, height: 400)).height > 0)
    }

    @Test func aTrailingClosureAfterATitleIsTheAction() {
        let banner = GitBanner(symbol: "arrow.down.circle", message: "Behind.", actionTitle: "Pull") {}
        let fields = Dictionary(uniqueKeysWithValues: Mirror(reflecting: banner).children.compactMap { child in
            child.label.map { ($0, child.value) }
        })
        #expect((fields["action"] as? (() -> Void)?).flatMap { $0 } != nil)
        #expect((fields["onDismiss"] as? (() -> Void)?).flatMap { $0 } == nil)
    }

    @Test func anAppCanWrapTheCommands() async {
        var features = GitFeatures.all
        features.remove([.merge], reason: "Only in the project root")
        let commands = HostCommands(features: features)
        await #expect(throws: GitFeatureError.self) { try await commands.perform(.merge("topic", squash: false)) }
    }
}
#endif
