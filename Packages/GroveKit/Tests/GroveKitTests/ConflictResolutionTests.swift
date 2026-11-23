// ConflictResolutionTests.swift
// GroveKitTests
//
// Saving an edited merge result: through the commands, onto a scratch repository's conflict.

import Foundation
@testable import GroveKit
import Testing

@MainActor
@Suite(.serialized)
final class ConflictResolutionTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-conflict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try git(["config", "user.name", "Tester"])
        try git(["config", "user.email", "tester@example.com"])
        try git(["config", "commit.gpgsign", "false"])
        try write("run.sh", "echo base\n")
        try git(["update-index", "--add", "--chmod=+x", "run.sh"])
        try git(["commit", "-q", "-m", "base"])
        try git(["switch", "-q", "-c", "other"])
        try write("run.sh", "echo theirs\n")
        try git(["commit", "-q", "-am", "theirs"])
        try git(["switch", "-q", "main"])
        try write("run.sh", "echo ours\n")
        try git(["commit", "-q", "-am", "ours"])
        _ = try? git(["merge", "other"])
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @Test func savingTheResultWritesItAndMarksItResolved() async throws {
        let repository = try await GitRepository(path: root, runner: LocalGitRunner())
        #expect(try await repository.status().contains { $0.path == "run.sh" && $0.isConflicted })
        try await RepositoryCommands(repository: repository)
            .perform(.saveConflictResolution(path: "run.sh", contents: "echo both\n"))
        #expect(try String(contentsOf: root.appendingPathComponent("run.sh"), encoding: .utf8) == "echo both\n")
        let entry = try #require(try await repository.status().first { $0.path == "run.sh" })
        #expect(!entry.isConflicted && entry.indexStatus == .modified)
        // An executable script stays executable, in the index and on disk.
        #expect(try git(["ls-files", "-s", "run.sh"]).hasPrefix("100755"))
        let mode = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("run.sh").path)[.posixPermissions]
        #expect((mode as? NSNumber)?.intValue == 0o755)
    }

    @Test func theViewModelSavesThroughItsCommands() async throws {
        let repository = MockGitRepository()
        let vm = WorkingCopyViewModel(repository: repository)
        let spy = SpyCommands()
        vm.commands = spy
        var reported: [(GroveKitAction, Bool)] = []
        vm.onAction = { reported.append(($0, $1)) }
        let entry = StatusEntry(id: "a", path: "a.txt", indexStatus: .conflicted, workdirStatus: .conflicted)
        await vm.saveConflictResolution(entry, contents: "merged\n")
        #expect(spy.performed == [.saveConflictResolution(path: "a.txt", contents: "merged\n")])
        #expect(reported.map(\.0) == [.resolveConflict] && reported.map(\.1) == [true])
    }

    @Test func theCommandNeedsNoFeature() {
        #expect(GitCommand.saveConflictResolution(path: "a", contents: "").requiredFeatures.isEmpty)
    }

    @Test func commitSaysWhyItCannotRun() async {
        let vm = WorkingCopyViewModel(repository: MockGitRepository())
        await vm.refresh()
        vm.commitSubject = ""
        #expect(vm.commitBlocker != nil)
        vm.commitSubject = "Fix"
        if !vm.conflictedFiles.isEmpty {
            #expect(vm.commitBlocker == "Resolve the conflicts first")
        } else if vm.stagedFiles.isEmpty {
            #expect(vm.commitBlocker == "Stage changes to commit")
        } else {
            #expect(vm.commitBlocker == nil && vm.canCommit)
        }
    }

    private func write(_ file: String, _ text: String) throws {
        try text.write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
    }

    @discardableResult
    private func git(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = root
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"]) { $1 }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
        return String(decoding: data, as: UTF8.self)
    }
}

@MainActor
private final class SpyCommands: GitCommandPerforming {
    let features = GitFeatures.all
    private(set) var performed: [GitCommand] = []

    func perform(_ command: GitCommand, progress: (@Sendable (Double) -> Void)?) async throws {
        performed.append(command)
    }
}
