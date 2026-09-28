// RemoteSyncTests.swift
// GroveTests
//
// Pull / push / sync / comparison against a scratch bare remote and two clones in a temp directory.

import Foundation
import Testing
@testable import Grove

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

    @Test func mergeStrategyOverridesPullRebaseConfig() async throws {
        try commit("b", file: "theirs.txt", message: "from b")
        try git(["push", "-q", "origin", "main"], in: "b")
        try commit("a", file: "mine.txt", message: "from a")
        try git(["config", "pull.rebase", "true"], in: "a")

        let repo = try await GitRepository(path: root.appendingPathComponent("a"))
        #expect(await repo.defaultPullStrategy() == .rebase)
        try await repo.pull(remote: nil, strategy: .merge, progress: nil)

        let parents = try git(["log", "-1", "--format=%P"], in: "a").split(separator: " ")
        #expect(parents.count == 2)
    }

    @Test func firstPushSetsUpstream() async throws {
        try git(["checkout", "-q", "-b", "feature"], in: "a")
        try commit("a", file: "feature.txt", message: "feature")

        let repo = try await GitRepository(path: root.appendingPathComponent("a"))
        try await repo.push(remote: "origin", forceWithLease: false, setUpstream: true, progress: nil)

        #expect(repo.currentBranch?.upstreamShortName == "origin/feature")
    }

    @Test func syncPublishesBranchWithoutUpstream() async throws {
        try git(["checkout", "-q", "-b", "sync"], in: "a")
        try commit("a", file: "sync.txt", message: "sync")

        let repo = try await GitRepository(path: root.appendingPathComponent("a"))
        try await repo.sync(remote: "origin", strategy: .merge, progress: nil)

        #expect(repo.currentBranch?.upstreamShortName == "origin/sync")
        #expect(try git(["branch", "--list", "sync"], in: "origin.git").contains("sync"))
    }

    @Test func comparisonShowsBothSides() async throws {
        try git(["checkout", "-q", "-b", "topic"], in: "a")
        try commit("a", file: "topic.txt", message: "topic only")
        try git(["checkout", "-q", "main"], in: "a")
        try commit("a", file: "main.txt", message: "main only")

        let repo = try await GitRepository(path: root.appendingPathComponent("a"))
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
