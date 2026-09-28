// BranchesReviewTests.swift
// GroveTests
//
// Batched branch tips, ahead/behind counts and their cache, against a scratch repository in a temp directory.

import Foundation
import Testing
@testable import Grove

@MainActor
@Suite(.serialized)
struct BranchesReviewTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try commit("base.txt", message: "initial")
        try git(["branch", "merged"])
        try git(["checkout", "-q", "-b", "topic"])
        try commit("topic.txt", message: "topic one")
        try commit("topic2.txt", message: "topic two")
        try git(["checkout", "-q", "-b", "feature/nested", "main"])
        try git(["checkout", "-q", "main"])
        try commit("main.txt", message: "main moved on")
    }

    // MARK: GitKit

    @Test func branchTipsReadEveryLocalBranchInOnePass() async throws {
        let repo = try await GitRepository(path: root)
        let tips = try await repo.branchTips()
        #expect(Set(tips.map(\.name)) == ["main", "merged", "topic", "feature/nested"])
        let topic = try #require(tips.first { $0.name == "topic" })
        #expect(topic.summary == "topic two")
        #expect(topic.authorName == "Grove Tests")
        #expect(topic.committerDate != nil)
        #expect(topic.sha.count == 40)
    }

    @Test func aheadBehindMatchesRevListFallback() async throws {
        let repo = try await GitRepository(path: root)
        let names = ["merged", "topic", "feature/nested"]
        let batched = try await repo.aheadBehind(branches: names, base: "main")
        let fallback = try await GitRepository.aheadBehindViaRevList(branches: names, base: "main",
                                                                     shell: GitShell(workingDirectory: root))
        #expect(batched == fallback)
        #expect(batched["topic"] == AheadBehind(ahead: 2, behind: 1))
        #expect(batched["merged"] == AheadBehind(ahead: 0, behind: 1))
    }

    @Test func aheadBehindOnlyCountsRequestedBranches() async throws {
        let repo = try await GitRepository(path: root)
        let counts = try await repo.aheadBehind(branches: ["topic"], base: "main")
        #expect(Array(counts.keys) == ["topic"])
    }

    @Test func viewModelCategorisesFromBatchedData() async throws {
        let vm = BranchesReviewViewModel(repository: try await GitRepository(path: root))
        await vm.refresh()
        #expect(vm.mergeStatusError == nil)
        let byName = Dictionary(uniqueKeysWithValues: vm.branches.map { ($0.name, $0) })
        #expect(byName["merged"]?.category == .merged)
        #expect(byName["feature/nested"]?.category == .merged)
        #expect(byName["topic"]?.category == .active)
        #expect(byName["topic"]?.ahead == 2)
        #expect(byName["main"]?.isPrimary == true)
        #expect(byName["topic"]?.lastCommitSummary == "topic two")
    }

    @Test func viewModelRecountsBranchWhoseTipMoved() async throws {
        let vm = BranchesReviewViewModel(repository: try await GitRepository(path: root))
        await vm.refresh()
        try git(["checkout", "-q", "merged"])
        try commit("more.txt", message: "no longer merged")
        try git(["checkout", "-q", "main"])
        await vm.refresh()
        let merged = try #require(vm.branches.first { $0.name == "merged" })
        #expect(merged.category == .active)
        #expect(merged.ahead == 1)
    }

    @Test func gitVersionParsesAppleAndPlainBuilds() {
        #expect(GitVersion.parse("git version 2.39.5 (Apple Git-154)\n") == GitVersion(major: 2, minor: 39))
        #expect(GitVersion.parse("git version 2.48.1") == GitVersion(major: 2, minor: 48))
        #expect(GitVersion.parse("garbage") == nil)
        #expect(GitVersion(major: 2, minor: 41) > GitVersion(major: 2, minor: 9))
    }

    // MARK: Cache

    @Test func cacheOnlyReportsChangedTips() {
        typealias Key = AheadBehindCache.Key
        var cache = AheadBehindCache()
        let first = [(name: "a", key: Key(branchSHA: "a1", baseSHA: "m1")),
                     (name: "b", key: Key(branchSHA: "b1", baseSHA: "m1"))]
        #expect(cache.missing(first) == ["a", "b"])
        cache.update(first, fresh: ["a": AheadBehind(ahead: 1, behind: 0), "b": AheadBehind(ahead: 0, behind: 2)])
        #expect(cache.missing(first).isEmpty)

        let bMoved = [first[0], (name: "b", key: Key(branchSHA: "b2", baseSHA: "m1"))]
        #expect(cache.missing(bMoved) == ["b"])

        let baseMoved = first.map { (name: $0.name, key: Key(branchSHA: $0.key.branchSHA, baseSHA: "m2")) }
        #expect(cache.missing(baseMoved) == ["a", "b"])
        cache.update(baseMoved, fresh: [:])
        #expect(cache.missing(first) == ["a", "b"], "Entries for old tips are pruned")
    }

    // MARK: Helpers

    private func commit(_ file: String, message: String) throws {
        try Data(message.utf8).write(to: root.appendingPathComponent(file))
        try git(["add", "."])
        try git(["-c", "user.name=Grove Tests", "-c", "user.email=tests@example.com", "commit", "-q", "-m", message])
    }

    @discardableResult
    private func git(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
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
