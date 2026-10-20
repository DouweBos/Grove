// RemoteSyncTests.swift
// GroveKitTests
//
// Pull / push / sync / comparison against a scratch bare remote and two clones in a temp directory.

import Foundation
import os
import Testing
@testable import GroveKit

@MainActor
@Suite(.serialized)
struct RemoteSyncTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-remote-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "--bare", "-b", "main", "origin.git"])
        try git(["clone", "-q", "origin.git", "a"])
        try configure("a")
        try commit("a", file: "base.txt", message: "initial")
        try git(["push", "-q", "origin", "main"], in: "a")
        try git(["clone", "-q", "origin.git", "b"])
        try configure("b")
    }

    // MARK: Tests

    @MainActor
    @Test func refsCarryThePullDefaultSoDialogsOpenOnIt() async throws {
        // Set locally either way, so the machine's global config doesn't decide the outcome.
        try git(["config", "pull.rebase", "false"], in: "a")
        let repo = try await GitRepository(path: root.appendingPathComponent("a"), runner: LocalGitRunner())
        let refs = RepositoryRefs(repository: repo, readsStatus: false)
        #expect(refs.defaultPullStrategy == nil)
        await refs.refresh()
        #expect(refs.defaultPullStrategy == .merge)

        try git(["config", "pull.rebase", "true"], in: "a")
        await refs.refresh()
        #expect(refs.defaultPullStrategy == .rebase)
    }

    @Test func mergeStrategyOverridesPullRebaseConfig() async throws {
        try commit("b", file: "theirs.txt", message: "from b")
        try git(["push", "-q", "origin", "main"], in: "b")
        try commit("a", file: "mine.txt", message: "from a")
        try git(["config", "pull.rebase", "true"], in: "a")

        let repo = try await GitRepository(path: root.appendingPathComponent("a"), runner: LocalGitRunner())
        #expect(await repo.defaultPullStrategy() == .rebase)
        try await repo.pull(remote: nil, strategy: .merge, progress: nil)

        let parents = try git(["log", "-1", "--format=%P"], in: "a").split(separator: " ")
        #expect(parents.count == 2)
    }

    @Test func pullReportsProgressUpToDone() async throws {
        try commit("b", file: "theirs.txt", message: "from b")
        try git(["push", "-q", "origin", "main"], in: "b")

        let repo = try await GitRepository(path: root.appendingPathComponent("a"), runner: LocalGitRunner())
        let values = OSAllocatedUnfairLock(initialState: [Double]())
        try await repo.pull(remote: nil, strategy: .merge) { value in values.withLock { $0.append(value) } }

        let reported = values.withLock { $0 }
        #expect(reported.count > 2)
        #expect(reported == reported.sorted())
        #expect(reported.last == 1)
    }

    @Test func pullRetriesAFetchThatRacedAnotherFetch() async throws {
        try commit("b", file: "theirs.txt", message: "from b")
        try git(["push", "-q", "origin", "main"], in: "b")

        let runner = RacingRunner()
        let repo = try await GitRepository(path: root.appendingPathComponent("a"), runner: runner)
        try await repo.pull(remote: nil, strategy: .merge, progress: nil)

        #expect(runner.streamedCommands == 2)
        #expect(try git(["log", "-1", "--format=%s"], in: "a").trimmingCharacters(in: .whitespacesAndNewlines) == "from b")
    }

    @Test func pullingAnotherBranchWithRebaseRebasesOntoIt() async throws {
        // `feature` tracks origin/feature; main moves on in the other clone.
        try git(["checkout", "-q", "-b", "feature"], in: "a")
        try commit("a", file: "feature.txt", message: "feature work")
        try git(["push", "-q", "-u", "origin", "feature"], in: "a")
        try commit("b", file: "main.txt", message: "main moved on")
        try git(["push", "-q", "origin", "main"], in: "b")

        let repo = try await GitRepository(path: root.appendingPathComponent("a"), runner: LocalGitRunner())
        try await repo.pull(remote: "origin", branch: "main", strategy: .rebase, options: PullOptions(), progress: nil)

        let subjects = try git(["log", "--format=%s", "-3"], in: "a").split(separator: "\n").map(String.init)
        #expect(subjects == ["feature work", "main moved on", "initial"])
        #expect(try git(["rev-parse", "--abbrev-ref", "HEAD"], in: "a").trimmingCharacters(in: .whitespacesAndNewlines) == "feature")
        #expect(try git(["rev-list", "--merges", "--count", "HEAD"], in: "a").trimmingCharacters(in: .whitespacesAndNewlines) == "0")
    }

    @Test func skipHooksBypassesCommitMsgHookOnMergePull() async throws {
        try commit("a", file: "a.txt", message: "local")
        try commit("b", file: "b.txt", message: "remote")
        try git(["push", "-q", "origin", "main"], in: "b")
        let hook = root.appendingPathComponent("a/.git/hooks/commit-msg")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)

        let repo = try await GitRepository(path: root.appendingPathComponent("a"), runner: LocalGitRunner())
        await #expect(throws: (any Error).self) {
            try await repo.pull(remote: nil, branch: nil, strategy: .merge, options: PullOptions(), progress: nil)
        }
        try git(["merge", "--abort"], in: "a")
        try await repo.pull(remote: nil, branch: nil, strategy: .merge, options: PullOptions(skipHooks: true), progress: nil)

        #expect(try git(["rev-list", "--merges", "--count", "HEAD"], in: "a").trimmingCharacters(in: .whitespacesAndNewlines) == "1")
    }

    @Test func firstPushSetsUpstream() async throws {
        try git(["checkout", "-q", "-b", "feature"], in: "a")
        try commit("a", file: "feature.txt", message: "feature")

        let repo = try await GitRepository(path: root.appendingPathComponent("a"), runner: LocalGitRunner())
        try await repo.push(remote: "origin", forceWithLease: false, setUpstream: true, progress: nil)

        #expect(repo.currentBranch?.upstreamShortName == "origin/feature")
    }

    @Test func pushesToDifferentlyNamedRemoteBranch() async throws {
        try git(["checkout", "-q", "-b", "feature"], in: "a")
        try commit("a", file: "feature.txt", message: "feature")

        let repo = try await GitRepository(path: root.appendingPathComponent("a"), runner: LocalGitRunner())
        try await repo.push(remote: "origin", branch: "review/feature", forceWithLease: false, setUpstream: true,
                            options: PushOptions(), progress: nil)

        #expect(repo.currentBranch?.upstreamShortName == "origin/review/feature")
        #expect(try git(["branch", "--list", "review/feature"], in: "origin.git").contains("review/feature"))
    }

    @Test func skipHooksBypassesPrePushHook() async throws {
        try commit("a", file: "a.txt", message: "local")
        let hook = root.appendingPathComponent("a/.git/hooks/pre-push")
        try Data("#!/bin/sh\nexit 1\n".utf8).write(to: hook)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hook.path)

        let repo = try await GitRepository(path: root.appendingPathComponent("a"), runner: LocalGitRunner())
        await #expect(throws: (any Error).self) {
            try await repo.push(remote: "origin", branch: "main", forceWithLease: false, setUpstream: false,
                                options: PushOptions(), progress: nil)
        }
        try await repo.push(remote: "origin", branch: "main", forceWithLease: false, setUpstream: false,
                            options: PushOptions(skipHooks: true), progress: nil)

        #expect(try git(["log", "-1", "--format=%s", "main"], in: "origin.git").contains("local"))
    }

    @Test func syncPublishesBranchWithoutUpstream() async throws {
        try git(["checkout", "-q", "-b", "sync"], in: "a")
        try commit("a", file: "sync.txt", message: "sync")

        let repo = try await GitRepository(path: root.appendingPathComponent("a"), runner: LocalGitRunner())
        try await repo.sync(remote: "origin", strategy: .merge, progress: nil)

        #expect(repo.currentBranch?.upstreamShortName == "origin/sync")
        #expect(try git(["branch", "--list", "sync"], in: "origin.git").contains("sync"))
    }

    @Test func comparisonShowsBothSides() async throws {
        try git(["checkout", "-q", "-b", "topic"], in: "a")
        try commit("a", file: "topic.txt", message: "topic only")
        try git(["checkout", "-q", "main"], in: "a")
        try commit("a", file: "main.txt", message: "main only")

        let repo = try await GitRepository(path: root.appendingPathComponent("a"), runner: LocalGitRunner())
        let comparison = try await repo.compareBranches(base: "main", compare: "topic")

        #expect(comparison.onlyInBase.map(\.summary) == ["main only"])
        #expect(comparison.onlyInCompare.map(\.summary) == ["topic only"])
        #expect(comparison.files.map(\.path) == ["topic.txt"])
    }

    @Test func parsesNumstatIncludingBinary() {
        let stats = GitRepository.parseNumstat("3\t1\tSources/a.swift\n-\t-\timage.png\n")
        #expect(stats == [ChangedFileStat(path: "Sources/a.swift", additions: 3, deletions: 1),
                          ChangedFileStat(path: "image.png", additions: nil, deletions: nil)])
    }

    // MARK: Helpers

    private func configure(_ clone: String) throws {
        try git(["config", "user.name", "Tester"], in: clone)
        try git(["config", "user.email", "tester@example.com"], in: clone)
        try git(["config", "commit.gpgsign", "false"], in: clone)
    }

    private func commit(_ clone: String, file: String, message: String) throws {
        try Data(message.utf8).write(to: root.appendingPathComponent(clone).appendingPathComponent(file))
        try git(["add", "."], in: clone)
        try git(["commit", "-q", "-m", message], in: clone)
    }

    @discardableResult
    private func git(_ args: [String], in directory: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory.map { root.appendingPathComponent($0) } ?? root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw GitShellError.nonZeroExit(command: args.joined(separator: " "), exitCode: process.terminationStatus, stderr: text)
        }
        return text
    }
}

/// Loses the first streamed command to another fetch, as when a tool fetches the same remote mid-pull.
private nonisolated final class RacingRunner: GitRunner, @unchecked Sendable {
    let local = LocalGitRunner()
    private let streamed = OSAllocatedUnfairLock(initialState: 0)
    var streamedCommands: Int { streamed.withLock { $0 } }

    func run(_ invocation: GitInvocation) async throws -> ShellResult { try await local.run(invocation) }
    func runStreaming(_ invocation: GitInvocation, onStderr: @escaping @Sendable (String) -> Void) async throws -> ShellResult {
        let count = streamed.withLock { $0 += 1; return $0 }
        guard count > 1 else {
            return ShellResult(stdout: "", stderr: "error: cannot lock ref 'refs/remotes/origin/main': is at aaa but expected bbb\n",
                               exitCode: 1)
        }
        return try await local.runStreaming(invocation, onStderr: onStderr)
    }
    var temporaryDirectory: URL { local.temporaryDirectory }
    func itemKind(at url: URL) async -> FileItemKind? { await local.itemKind(at: url) }
    func readFile(at url: URL) async throws -> Data { try await local.readFile(at: url) }
    func writeFile(_ data: Data, to url: URL, executable: Bool) async throws { try await local.writeFile(data, to: url, executable: executable) }
    func removeItem(at url: URL) async throws { try await local.removeItem(at: url) }
    func createDirectory(at url: URL) async throws { try await local.createDirectory(at: url) }
    func moveItem(at source: URL, to destination: URL) async throws { try await local.moveItem(at: source, to: destination) }
    func contentsOfDirectory(at url: URL) async throws -> [String] { try await local.contentsOfDirectory(at: url) }
}
