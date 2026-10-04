// PathLimitedDiffTests.swift
// GroveKitTests
//
// File History diffs one path per commit instead of the whole commit, against a scratch repository.

import Foundation
import Testing
@testable import GroveKit

@MainActor
@Suite(.serialized)
struct PathLimitedDiffTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-pathdiff-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
    }

    @Test func limitsDiffToPath() async throws {
        try write("a.txt", "one\ntwo\nthree\nfour\nfive\n")
        try commitAll("add a")
        try write("a.txt", "one\ntwo\nTHREE\nfour\nfive\n")
        try write("b.txt", "b\n")
        try commitAll("change a, add b")
        let repo = try await GitRepository(path: root, runner: LocalGitRunner())
        let files = try await repo.diffForCommit("HEAD", path: "a.txt")
        #expect(files.map(\.path) == ["a.txt"])
        #expect(files.first?.status == .modified)
    }

    @Test func fileHistoryFollowsRenameIntoFullDiff() async throws {
        try write("a.txt", "one\ntwo\nthree\nfour\nfive\nsix\nseven\neight\n")
        try commitAll("add a")
        try git(["mv", "a.txt", "c.txt"])
        try write("c.txt", "one\ntwo\nthree\nfour\nfive\nsix\nseven\nEIGHT\n")
        try commitAll("rename a to c")
        let repo = try await GitRepository(path: root, runner: LocalGitRunner())
        let vm = FileHistoryViewModel(repository: repo, filePath: "c.txt")
        await vm.loadHistory()
        #expect(vm.commits.count == 2)
        // The rename commit reads as an addition when limited to c.txt; the full diff shows the rename.
        #expect(vm.fileDiff?.oldPath == "a.txt")
    }

    @Test func rangeDiffSpansSeveralCommits() async throws {
        try write("a.txt", "one\n")
        try commitAll("add a")
        let base = try git(["rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        try write("a.txt", "two\n")
        try commitAll("change a")
        try write("b.txt", "b\n")
        try commitAll("add b")
        let repo = try await GitRepository(path: root, runner: LocalGitRunner())
        let files = try await repo.diff(from: base, to: "HEAD")
        #expect(files.map(\.path).sorted() == ["a.txt", "b.txt"])
        #expect(files.first { $0.path == "b.txt" }?.status == .added)
        #expect(files.first { $0.path == "a.txt" }?.stats == DiffStats(additions: 1, deletions: 1))
    }

    @Test func patchParsesWithoutARepository() {
        let patch = "diff --git a/new.txt b/new.txt\nnew file mode 100644\n--- /dev/null\n+++ b/new.txt\n@@ -0,0 +1 @@\n+hi"
        let files = DiffParser.fileDiffs(patch: patch)
        #expect(files.map(\.path) == ["new.txt"])
        #expect(files.first?.status == .added)
    }

    // MARK: Helpers

    private func write(_ file: String, _ text: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(file))
    }

    private func commitAll(_ message: String) throws {
        try git(["add", "-A"])
        try git(["commit", "-q", "-m", message])
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
        let text = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw GitShellError.nonZeroExit(command: args.joined(separator: " "), exitCode: process.terminationStatus, stderr: text)
        }
        return text
    }
}
