// SnapshotTests.swift
// GroveKitTests
//
// Save Snapshot stores a stash without touching the working copy, against a scratch repository.

import Foundation
import Testing
@testable import GroveKit

@MainActor
@Suite(.serialized)
struct SnapshotTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-snapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
        try write("a.txt", "one\n")
        try git(["add", "-A"])
        try git(["commit", "-q", "-m", "initial"])
    }

    @Test func keepsTheWorkingCopyAndRestoresEverythingLater() async throws {
        try write("a.txt", "edited\n")
        try write("b.txt", "staged\n")
        try git(["add", "b.txt"])
        try write("c.txt", "untracked\n")
        let repo = try await GitRepository(path: root, runner: LocalGitRunner())
        let before = try await repo.status()

        #expect(try await repo.saveSnapshot(message: "Before refactor", includeUntracked: true))
        #expect(try await repo.status() == before)
        let stashes = try await repo.stashes()
        #expect(stashes.count == 1)
        #expect(stashes.first?.message.contains("Before refactor") == true)

        try git(["reset", "-q", "--hard"])
        try git(["clean", "-fdq"])
        try await repo.stashApply(index: 0, drop: false)
        #expect(try read("a.txt") == "edited\n")
        #expect(try read("b.txt") == "staged\n")
        #expect(try read("c.txt") == "untracked\n")
    }

    @Test func snapshotsOnlyUntrackedFiles() async throws {
        try write("new.txt", "fresh\n")
        let repo = try await GitRepository(path: root, runner: LocalGitRunner())
        #expect(try await repo.saveSnapshot(message: "Only new", includeUntracked: true))
        try FileManager.default.removeItem(at: root.appendingPathComponent("new.txt"))
        try await repo.stashApply(index: 0, drop: false)
        #expect(try read("new.txt") == "fresh\n")
    }

    @Test func reportsWhenThereIsNothingToSave() async throws {
        try write("new.txt", "fresh\n")
        let repo = try await GitRepository(path: root, runner: LocalGitRunner())
        #expect(try await repo.saveSnapshot(message: "Nothing tracked", includeUntracked: false) == false)
        #expect(try await repo.stashes().isEmpty)
    }

    // MARK: Helpers

    private func write(_ file: String, _ text: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(file))
    }

    private func read(_ file: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
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
