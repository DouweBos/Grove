// GitRunnerTests.swift
// GroveKitTests
//
// Every git process and worktree file the engine touches goes through its runner, against a scratch repository.

import Foundation
import os
import Testing
@testable import GroveKit

/// Forwards to a local runner and records what passed through, as a remote runner would see it.
private final class RecordingRunner: GitRunner, @unchecked Sendable {
    let local = LocalGitRunner()
    private let log = OSAllocatedUnfairLock(initialState: (commands: [[String]](), reads: [URL](), writes: [URL]()))

    var commands: [[String]] { log.withLock { $0.commands } }
    var reads: [URL] { log.withLock { $0.reads } }
    var writes: [URL] { log.withLock { $0.writes } }

    func run(_ invocation: GitInvocation) async throws -> ShellResult {
        log.withLock { $0.commands.append(invocation.arguments) }
        return try await local.run(invocation)
    }

    func runStreaming(_ invocation: GitInvocation, onStderr: @escaping @Sendable (String) -> Void) async throws -> ShellResult {
        log.withLock { $0.commands.append(invocation.arguments) }
        return try await local.runStreaming(invocation, onStderr: onStderr)
    }

    var temporaryDirectory: URL { local.temporaryDirectory }
    func itemKind(at url: URL) async -> FileItemKind? { await local.itemKind(at: url) }

    func readFile(at url: URL) async throws -> Data {
        log.withLock { $0.reads.append(url) }
        return try await local.readFile(at: url)
    }

    func writeFile(_ data: Data, to url: URL, executable: Bool) async throws {
        log.withLock { $0.writes.append(url) }
        try await local.writeFile(data, to: url, executable: executable)
    }

    func createDirectory(at url: URL) async throws { try await local.createDirectory(at: url) }
    func removeItem(at url: URL) async throws { try await local.removeItem(at: url) }
    func moveItem(at source: URL, to destination: URL) async throws { try await local.moveItem(at: source, to: destination) }
    func contentsOfDirectory(at url: URL) async throws -> [String] { try await local.contentsOfDirectory(at: url) }
}

@MainActor
@Suite(.serialized)
struct GitRunnerTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grovekit-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func git(_ arguments: [String]) async throws {
        try await GitShell(workingDirectory: root, runner: LocalGitRunner()).run(arguments)
    }

    @Test func repositoryRunsGitThroughItsRunner() async throws {
        try await git(["init", "-q", "-b", "main"])
        let runner = RecordingRunner()
        let repo = try await GitRepository(path: root, runner: runner)
        _ = try await repo.status()
        #expect(runner.commands.first == ["rev-parse", "--git-dir"])
        #expect(runner.commands.contains { $0.contains("status") })
    }

    @Test func worktreeFilesAreReadAndWrittenThroughTheRunner() async throws {
        try await git(["init", "-q", "-b", "main"])
        try "hello\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let runner = RecordingRunner()
        let repo = try await GitRepository(path: root, runner: runner)

        try await repo.ignore(patterns: ["*.log"], localOnly: false)
        #expect(runner.writes.map(\.lastPathComponent) == [".gitignore"])
        #expect(try await repo.fileContents(path: "a.txt", revision: nil) == "hello\n")
        #expect(runner.reads.map(\.lastPathComponent).contains("a.txt"))
    }

    @Test func fileActionsGoThroughTheRunner() async throws {
        try await git(["init", "-q", "-b", "main"])
        try "a\n".write(to: root.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "b\n".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        let viewModel = WorkingCopyViewModel(repository: try await GitRepository(path: root, runner: RecordingRunner()))
        await viewModel.refresh()
        let a = try #require(viewModel.statusEntries.first { $0.path == "a.txt" })

        await viewModel.rename(a, to: "b.txt")
        #expect(viewModel.errorMessage == "\u{201C}b.txt\u{201D} already exists.")

        // This runner has no Trash, so the file stays and the failure shows.
        await viewModel.moveToTrash([a])
        #expect(viewModel.errorMessage != nil)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("a.txt").path))
    }

    @Test func worktreeLinksResolveThroughTheRunner() async throws {
        try await git(["init", "-q", "-b", "main", "main"])
        let main = root.appendingPathComponent("main")
        try await GitShell(workingDirectory: main, runner: LocalGitRunner())
            .run(["-c", "user.name=T", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"])
        let linked = root.appendingPathComponent("linked").path
        try await GitShell(workingDirectory: main, runner: LocalGitRunner()).run(["worktree", "add", "-q", "-b", "topic", linked])
        let runner = RecordingRunner()

        #expect(await WorktreeResolver.mainRepositoryPath(forWorktreeAt: linked, runner: runner) == main.standardizedFileURL.path)
        #expect(runner.reads.map(\.lastPathComponent).contains(".git"))
        let worktrees = await WorktreeResolver.linkedWorktrees(ofRepositoryAt: main.path, runner: runner)
        #expect(worktrees.map(\.name) == ["topic"])
        #expect(worktrees == WorktreeResolver.linkedWorktrees(ofRepositoryAt: main.path))
    }

    @Test func localRunnerFileOperationsRoundTrip() async throws {
        let runner = LocalGitRunner()
        let file = root.appendingPathComponent("nested/dir/script.sh")
        try await runner.writeString("#!/bin/sh\n", to: file, executable: true)
        #expect(await runner.itemKind(at: file) == .file)
        #expect(await runner.itemKind(at: file.deletingLastPathComponent()) == .directory)
        #expect(FileManager.default.isExecutableFile(atPath: file.path))
        #expect(await runner.readString(at: file) == "#!/bin/sh\n")
        let moved = root.appendingPathComponent("nested/moved.sh")
        try await runner.moveItem(at: file, to: moved)
        #expect(try await runner.contentsOfDirectory(at: root.appendingPathComponent("nested")).sorted() == ["dir", "moved.sh"])
        try await runner.removeItem(at: moved)
        #expect(await runner.fileExists(at: moved) == false)
    }

    @Test func providerSeesTheShellEnvironmentAndCallOverridesWin() async throws {
        let runner = LocalGitRunner { _, base in
            ["GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_0": "grovekit.value", "GIT_CONFIG_VALUE_0": base["GROVEKIT_SHELL"] ?? "none"]
        }
        let shell = GitShell(workingDirectory: root, runner: runner, extraEnvironment: ["GROVEKIT_SHELL": "shell"])
        let fromProvider = try await shell.run(["config", "--get", "grovekit.value"]).stdout
        #expect(fromProvider.trimmingCharacters(in: .whitespacesAndNewlines) == "shell")
        let overridden = try await shell.run(["config", "--get", "grovekit.value"], environment: ["GIT_CONFIG_VALUE_0": "call"]).stdout
        #expect(overridden.trimmingCharacters(in: .whitespacesAndNewlines) == "call")
    }
}
