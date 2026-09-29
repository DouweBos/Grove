// WorktreeRemovalTests.swift
// GroveTests
//
// Removing a worktree with its branch, keeping its branch out of cleanup, and letting go of tabs that showed it.

import Foundation
import Testing
@testable import Grove

@MainActor
@Suite(.serialized)
struct WorktreeRemovalTests {

    private let root: URL
    private var repo: URL { root.appendingPathComponent("main") }
    private var worktree: URL { root.appendingPathComponent("wt") }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grove-wt-remove-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main", repo.path], in: root)
        try commit("base.txt", in: repo)
        try git(["worktree", "add", "-q", "-b", "feature", worktree.path], in: repo)
    }

    // MARK: Sidebar

    @Test func removingWithUncommittedChangesNeedsForceThenDeletesTheBranch() async throws {
        let vm = SidebarViewModel(repository: try await GitRepository(path: repo))
        await vm.refresh()
        var removed: (String, String?)?
        vm.onWorktreeRemoved = { removed = ($0, $1) }
        let branch = try #require(vm.localBranches.first { $0.name == "feature" })
        let linked = try #require(vm.worktree(checkingOut: branch))
        try Data("wip".utf8).write(to: worktree.appendingPathComponent("wip.txt"))

        await #expect(throws: (any Error).self) {
            try await vm.removeWorktree(linked, force: false, deleting: branch, forceBranch: false)
        }
        #expect(removed == nil)

        try await vm.removeWorktree(linked, force: true, deleting: branch, forceBranch: false)
        #expect(!FileManager.default.fileExists(atPath: worktree.path))
        #expect(try git(["branch", "--list", "feature"], in: repo).isEmpty)
        #expect(removed?.0 == linked.path)
        #expect(WorktreeResolver.isSameFolder(removed?.1 ?? "", repo.path))
    }

    @Test func retryAfterAnUnmergedBranchSkipsTheRemovedWorktree() async throws {
        try commit("feature.txt", in: worktree)
        let vm = SidebarViewModel(repository: try await GitRepository(path: repo))
        await vm.refresh()
        let branch = try #require(vm.localBranches.first { $0.name == "feature" })
        let linked = try #require(vm.worktree(checkingOut: branch))

        await #expect(throws: (any Error).self) {
            try await vm.removeWorktree(linked, force: false, deleting: branch, forceBranch: false)
        }
        #expect(!FileManager.default.fileExists(atPath: worktree.path))
        await vm.refresh()
        try await vm.removeWorktree(linked, force: false, deleting: branch, forceBranch: true)
        #expect(try git(["branch", "--list", "feature"], in: repo).isEmpty)
    }

    // MARK: Helpers

    private func session(in window: WindowViewModel, at path: String) async throws -> RepositorySession {
        for _ in 0..<50 {
            if let loaded = window.sessions[path] { return loaded.session }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw CancellationError()
    }

    private func commit(_ file: String, in directory: URL) throws {
        try Data(file.utf8).write(to: directory.appendingPathComponent(file))
        try git(["add", "."], in: directory)
        try git(["-c", "user.name=Grove Tests", "-c", "user.email=tests@example.com", "commit", "-q", "-m", file], in: directory)
    }

    @discardableResult
    private func git(_ args: [String], in directory: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = directory
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
