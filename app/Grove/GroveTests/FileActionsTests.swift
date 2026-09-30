// FileActionsTests.swift
// GroveTests
//
// Ignore, Stop Tracking and Rename from the Changes list, against a scratch repository.

import Foundation
import Testing
@testable import Grove

struct GitIgnoreFileTests {

    @Test func buildsAnchoredPatterns() {
        #expect(GitIgnoreFile.pattern(forFile: "build/out.log") == "/build/out.log")
        #expect(GitIgnoreFile.pattern(forExtension: "log") == "*.log")
        #expect(GitIgnoreFile.pattern(forFolder: "build/") == "/build/")
    }

    @Test func escapesGlobsAndLeadingMarkers() {
        #expect(GitIgnoreFile.escape("a[1]*.txt") == "a\\[1]\\*.txt")
        #expect(GitIgnoreFile.escape("#notes") == "\\#notes")
        #expect(GitIgnoreFile.escape("!keep") == "\\!keep")
        #expect(GitIgnoreFile.escape("trail ") == "trail\\ ")
    }

    @Test func appendsOnlyMissingPatternsOnNewLines() {
        #expect(GitIgnoreFile.appending(["*.log"], to: "") == "*.log\n")
        #expect(GitIgnoreFile.appending(["*.log", "/tmp/"], to: "*.log") == "*.log\n/tmp/\n")
        #expect(GitIgnoreFile.appending(["*.log"], to: "*.log\n") == "*.log\n")
    }
}

@MainActor
@Suite(.serialized)
struct FileActionsTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-fileactions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
        try write("tracked.txt", "tracked\n")
        try git(["add", "-A"])
        try git(["commit", "-q", "-m", "initial"])
    }

    @Test func ignoreHidesFilesFromStatus() async throws {
        try write("debug.log", "x\n")
        try write("notes.md", "x\n")
        let repo = try await GitRepository(path: root)
        try await repo.ignore(patterns: [GitIgnoreFile.pattern(forExtension: "log")], localOnly: false)
        try await repo.ignore(patterns: [GitIgnoreFile.pattern(forFile: "notes.md")], localOnly: true)
        let paths = try await repo.status().map(\.path)
        #expect(paths == [".gitignore"])
        let exclude = try String(contentsOf: root.appendingPathComponent(".git/info/exclude"), encoding: .utf8)
        #expect(exclude.hasSuffix("/notes.md\n"))
    }

    @Test func stopTrackingKeepsTheFile() async throws {
        let repo = try await GitRepository(path: root)
        try await repo.stopTracking(paths: ["tracked.txt"])
        let entry = try #require(try await repo.status().first { $0.path == "tracked.txt" && $0.indexStatus == .deleted })
        #expect(entry.indexStatus == .deleted)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("tracked.txt").path))
    }

    @Test func movesTrackedAndUntrackedFiles() async throws {
        try write("new.txt", "new\n")
        let repo = try await GitRepository(path: root)
        try await repo.moveFile(from: "tracked.txt", to: "docs/renamed.txt")
        try await repo.moveFile(from: "new.txt", to: "moved.txt")
        let status = try await repo.status()
        #expect(status.contains { $0.path == "docs/renamed.txt" && $0.indexStatus == .renamed })
        #expect(status.contains { $0.path == "moved.txt" && $0.workdirStatus == .untracked })
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("new.txt").path))
    }

    @Test func actionsFollowTheMultiSelection() async throws {
        try write("a.log", "a\n")
        try write("b.log", "b\n")
        let repo = try await GitRepository(path: root)
        let vm = WorkingCopyViewModel(repository: repo)
        await vm.refresh()
        let entries = vm.unstagedFiles
        await vm.click(entries[0], side: .unstaged, extend: false, toggle: false)
        await vm.click(entries[1], side: .unstaged, extend: false, toggle: true)
        let acting = vm.actionEntries(for: entries[0], side: .unstaged)
        #expect(acting.map(\.path) == ["a.log", "b.log"])
        #expect(vm.ignoreTargets(for: acting) == [.files, .fileExtension("log")])
        await vm.ignore(.fileExtension("log"), of: acting, localOnly: false)
        #expect(vm.statusEntries.map(\.path) == [".gitignore"])
    }

    @Test func discardCoversTheMultiSelection() async throws {
        try write("tracked.txt", "edited\n")
        try write("new.txt", "new\n")
        try write("kept.txt", "kept\n")
        let repo = try await GitRepository(path: root)
        let vm = WorkingCopyViewModel(repository: repo)
        await vm.refresh()
        let tracked = try #require(vm.unstagedFiles.first { $0.path == "tracked.txt" })
        let new = try #require(vm.unstagedFiles.first { $0.path == "new.txt" })
        await vm.click(tracked, side: .unstaged, extend: false, toggle: false)
        await vm.click(new, side: .unstaged, extend: false, toggle: true)
        let acting = vm.actionEntries(for: tracked, side: .unstaged)
        vm.requestDiscard(acting)
        #expect(vm.pendingDiscard?.count == 2)
        await vm.discard(acting)
        #expect(vm.statusEntries.map(\.path) == ["kept.txt"])
        #expect(try read("tracked.txt") == "tracked\n")
    }

    @Test func restoreAsksFirstWhenTheFileHasLocalChanges() async throws {
        try write("tracked.txt", "second\n")
        try git(["commit", "-qam", "second"])
        try write("tracked.txt", "local edit\n")
        let repo = try await GitRepository(path: root)
        let vm = FileHistoryViewModel(repository: repo, filePath: "tracked.txt")
        await vm.loadHistory()
        let initial = try #require(vm.commits.last)
        await vm.requestRestore(initial)
        #expect(vm.pendingRestore?.id == initial.id)
        await vm.restore(initial)
        #expect(try read("tracked.txt") == "tracked\n")
        #expect(vm.restoredCommit?.id == initial.id)
    }

    @Test func restoreWritesAcrossARename() async throws {
        try git(["mv", "tracked.txt", "moved.txt"])
        try git(["commit", "-qm", "rename"])
        try write("moved.txt", "after rename\n")
        try git(["commit", "-qam", "edit"])
        let repo = try await GitRepository(path: root)
        let vm = FileHistoryViewModel(repository: repo, filePath: "moved.txt")
        await vm.loadHistory()
        let initial = try #require(vm.commits.last)
        await vm.requestRestore(initial)
        #expect(vm.pendingRestore == nil)
        #expect(vm.errorMessage == nil)
        #expect(vm.commits.count == 3)
        #expect(try read("moved.txt") == "tracked\n")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("tracked.txt").path))
    }

    // MARK: Helpers

    private func read(_ file: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
    }

    private func write(_ file: String, _ text: String) throws {
        try Data(text.utf8).write(to: root.appendingPathComponent(file))
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
