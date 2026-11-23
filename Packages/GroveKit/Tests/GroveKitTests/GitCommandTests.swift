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
        .pushBranch("topic", remote: "origin", as: "review", forceWithLease: true, setUpstream: true,
                    options: PushOptions(recurseSubmodules: .check, skipHooks: true, tags: .follow)),
        .pull(remote: nil, branch: nil, strategy: .merge, options: PullOptions(verifySignatures: true)),
        .sync(remote: nil, strategy: .rebase), .renameCurrentBranch(to: "renamed"),
        .stashAndCheckout("main"), .discardAndCheckout("main"), .saveConflictResolution(path: "a", contents: "b"),
        .cherryPick("abc"), .revert("abc"), .reset(to: "abc", mode: .hard), .reword("abc", message: "m"),
        .squash(["abc", "def"], message: "m"), .drop("abc"), .rebaseInteractive(onto: "abc", steps: [RebaseStep(sha: "def")]),
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

    @Test func optionsNeedTheirFeatures() {
        #expect(GitCommand.pull(remote: nil, branch: nil, strategy: .merge, options: PullOptions(verifySignatures: true))
            .requiredFeatures == [.verifySignatures])
        #expect(GitCommand.push(remote: "o", branch: "b", forceWithLease: false, setUpstream: false,
                                options: PushOptions(recurseSubmodules: .onDemand)).requiredFeatures == [.push, .recurseSubmodules])
        #expect(GitCommand.renameCurrentBranch(to: "x").requiredFeatures.isEmpty)
        #expect(GitCommand.stashAndCheckout("x").requiredFeatures == [.checkout])
    }

    @Test func historyRewritesNeedNoFeature() {
        let rewrites: [GitCommand] = [.cherryPick("a"), .revert("a"), .reset(to: "a", mode: .soft), .reword("a", message: "m"),
                                      .squash(["a", "b"], message: "m"), .drop("a"), .rebaseInteractive(onto: "a", steps: [])]
        #expect(rewrites.allSatisfy { $0.requiredFeatures.isEmpty })
    }
}
