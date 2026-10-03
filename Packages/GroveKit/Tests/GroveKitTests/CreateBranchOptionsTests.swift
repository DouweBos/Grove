// CreateBranchOptionsTests.swift
// GroveKitTests
//
// New Branch options: tracking the starting branch, a recorded parent, pinning, and pulling from the parent.

import Foundation
import Testing
@testable import GroveKit

@MainActor
@Suite(.serialized)
struct CreateBranchOptionsTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-newbranch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "T"])
        try git(["config", "user.email", "t@t"])
        try "base\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."])
        try git(["commit", "-qm", "base"])
    }

    @Test func trackAndParentAreApplied() async throws {
        let repo = try await GitRepository(path: root, runner: LocalGitRunner())
        try await repo.createBranch(name: "feature/x", from: "main", checkout: false, track: true, parent: "main")

        #expect(try git(["rev-parse", "--abbrev-ref", "feature/x@{upstream}"]).trimmed == "main")
        #expect(try await repo.branchParents() == ["feature/x": "main"])
    }

    @Test func noParentMeansNothingRecorded() async throws {
        let repo = try await GitRepository(path: root, runner: LocalGitRunner())
        try await repo.createBranch(name: "plain", from: "main", checkout: false, track: false, parent: nil)
        #expect(try await repo.branchParents().isEmpty)
        #expect((try? git(["rev-parse", "--abbrev-ref", "plain@{upstream}"])) == nil)
    }

    @Test func parentConfigParsesSlashedNames() {
        let output = "branch.feature/a/b.grove-parent main\nbranch.fix.grove-parent feature/a/b\nbranch.x.remote origin\n"
        #expect(GitRepository.parseBranchParents(output) == ["feature/a/b": "main", "fix": "feature/a/b"])
    }

    @Test func pullingTheLocalParentWithRebaseRebasesOntoIt() async throws {
        let repo = try await GitRepository(path: root, runner: LocalGitRunner())
        try await repo.createBranch(name: "child", from: "main", checkout: true, track: false, parent: "main")
        try "child\n".write(to: root.appendingPathComponent("c.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."]); try git(["commit", "-qm", "child work"])
        try git(["checkout", "-q", "main"])
        try "more\n".write(to: root.appendingPathComponent("m.txt"), atomically: true, encoding: .utf8)
        try git(["add", "."]); try git(["commit", "-qm", "main moved"])
        try git(["checkout", "-q", "child"])

        let reopened = try await GitRepository(path: root, runner: LocalGitRunner())
        try await reopened.pull(remote: ".", branch: "main", strategy: .rebase, options: PullOptions(), progress: nil)
        let subjects = try git(["log", "--format=%s", "-3"]).split(separator: "\n").map(String.init)
        #expect(subjects == ["child work", "main moved", "base"])
    }

    @discardableResult
    private func git(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        process.environment = env
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
        return String(decoding: data, as: UTF8.self)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
