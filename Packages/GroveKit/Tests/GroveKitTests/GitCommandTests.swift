// GitCommandTests.swift
// GroveKitTests

@testable import GroveKit
import Testing

@MainActor
struct GitCommandTests {

    private static let samples: [GitCommand] = [
        .fetch(remote: nil),
        .pull(remote: "origin", branch: "main", strategy: .merge, options: PullOptions(skipHooks: true)),
        .push(remote: "origin", branch: "main", forceWithLease: false, setUpstream: false, options: PushOptions(skipHooks: true)),
        .createBranch(name: "topic", from: nil, checkout: true, track: false, parent: nil),
        .renameBranch(from: "a", to: "b"), .deleteBranch(name: "a", force: false),
        .deleteRemoteBranch(name: "a", remote: "origin"), .setUpstream(branch: "a", upstream: "origin/a"),
        .checkout("main"), .merge("topic", squash: true), .rebase(onto: "main"),
        .createTag(name: "v1", at: nil, message: nil, sign: false), .deleteTag("v1"),
        .pushTag("v1", remote: nil), .pushAllTags(remote: nil),
        .addRemote(name: "up", url: "/tmp/up"), .removeRemote("up"), .setRemoteURL("/tmp/up", remote: "up"),
        .renameRemote(from: "up", to: "down"), .pruneRemote("down"), .branchFromStash(index: 0, name: "saved"),
        .stash(message: nil, includeUntracked: false, keepIndex: true, paths: nil), .applyStash(index: 0, drop: false),
        .dropStash(index: 0), .snapshot(message: "wip", includeUntracked: true),
    ]

    @Test(arguments: GitFeature.allCases)
    func nothingPerformsWithoutItsFeature(_ feature: GitFeature) async {
        var features = GitFeatures.all
        features.remove([feature], reason: "Not here")
        let commands = RepositoryCommands(repository: MockGitRepository(), features: features)
        for command in Self.samples where command.requiredFeatures.contains(feature) {
            await #expect(throws: GitFeatureError(feature: feature, reason: "Not here")) {
                try await commands.perform(command)
            }
        }
    }

    @Test func everythingIsSupportedByDefault() throws {
        let commands = RepositoryCommands(repository: MockGitRepository())
        for command in Self.samples { try commands.requireSupport(for: command) }
    }
}
