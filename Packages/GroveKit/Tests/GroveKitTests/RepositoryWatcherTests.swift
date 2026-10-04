// RepositoryWatcherTests.swift
// GroveKitTests
//
// Which changes a repository's watcher reacts to, for main and linked worktrees.

import Foundation
import Testing
@testable import GroveKit

@MainActor
@Suite(.serialized)
struct RepositoryWatcherTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grovekit-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private let linked = RepositoryWatcher.Layout(worktree: "/r/wt", gitDir: "/r/main/.git/worktrees/wt", commonDir: "/r/main/.git")
    private let main = RepositoryWatcher.Layout(worktree: "/r/main", gitDir: "/r/main/.git", commonDir: "/r/main/.git")

    @Test func linkedWorktreeIgnoresItsSiblings() {
        #expect(linked.watchedPaths == ["/r/wt", "/r/main/.git"])
        #expect(linked.isRelevant("/r/wt/src/a.swift"))
        #expect(linked.isRelevant("/r/main/.git/worktrees/wt/HEAD"))
        #expect(linked.isRelevant("/r/main/.git/worktrees/wt/index"))
        #expect(linked.isRelevant("/r/main/.git/refs/heads/topic"))
        #expect(linked.isRelevant("/r/main/.git/packed-refs"))
        #expect(!linked.isRelevant("/r/main/.git/worktrees/other/HEAD"))
        #expect(!linked.isRelevant("/r/main/.git/HEAD"))
        #expect(!linked.isRelevant("/r/main/.git/index"))
        #expect(!linked.isRelevant("/r/main/src/a.swift"))
    }

    @Test func mainWorktreeIgnoresLinkedOnes() {
        #expect(main.watchedPaths == ["/r/main"])
        #expect(main.isRelevant("/r/main/.git/HEAD"))
        #expect(main.isRelevant("/r/main/src/a.swift"))
        #expect(!main.isRelevant("/r/main/.git/worktrees/wt/HEAD"))
    }

    @Test func layoutComesFromGit() async throws {
        let shell = GitShell(workingDirectory: root, runner: LocalGitRunner())
        try await shell.run(["init", "-q", "-b", "main", "main"])
        let mainURL = root.appendingPathComponent("main")
        let mainShell = GitShell(workingDirectory: mainURL, runner: LocalGitRunner())
        try await mainShell.run(["-c", "user.name=T", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"])
        try await mainShell.run(["worktree", "add", "-q", "-b", "topic", root.appendingPathComponent("wt").path])

        let layout = await RepositoryWatcher.layout(of: root.appendingPathComponent("wt"), runner: LocalGitRunner())
        // git reports real paths (`/private/var` for `/var`), the same way for all three.
        #expect(layout.worktree.hasSuffix("\(root.lastPathComponent)/wt"))
        #expect(layout.commonDir.hasSuffix("\(root.lastPathComponent)/main/.git"))
        #expect(layout.gitDir == layout.commonDir + "/worktrees/wt")
        #expect(layout.watchedPaths == [layout.worktree, layout.commonDir])
    }

    @Test func siblingActivityDoesNotFireButSharedRefsDo() async throws {
        let mainURL = root.appendingPathComponent("main")
        try await GitShell(workingDirectory: root, runner: LocalGitRunner()).run(["init", "-q", "-b", "main", "main"])
        let mainShell = GitShell(workingDirectory: mainURL, runner: LocalGitRunner())
        try await mainShell.run(["-c", "user.name=T", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"])
        try await mainShell.run(["worktree", "add", "-q", "-b", "mine", root.appendingPathComponent("mine").path])
        let sibling = root.appendingPathComponent("sibling")
        try await mainShell.run(["worktree", "add", "-q", "-b", "theirs", sibling.path])

        let fired = Counter()
        let watcher = RepositoryWatcher(path: root.appendingPathComponent("mine"), runner: LocalGitRunner(), latency: 0.1) {
            fired.increment()
        }
        #expect(await watcher.start())
        defer { watcher.stop() }
        try await Task.sleep(for: .seconds(1))

        try Data("x\n".utf8).write(to: sibling.appendingPathComponent("file.txt"))
        try await GitShell(workingDirectory: sibling, runner: LocalGitRunner()).run(["add", "file.txt"])
        try await Task.sleep(for: .seconds(1.5))
        #expect(fired.value == 0)

        try await mainShell.run(["branch", "shared"])
        try await Task.sleep(for: .seconds(1.5))
        #expect(fired.value > 0)
    }

    @Test func runnerWithoutWatchingSaysSo() async {
        let watcher = RepositoryWatcher(path: root, runner: NoWatchRunner()) {}
        #expect(await watcher.start() == false)
    }
}

private nonisolated final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

/// The local runner without its watch, as a runner on another machine might be.
private nonisolated struct NoWatchRunner: GitRunner {
    let local = LocalGitRunner()
    func run(_ invocation: GitInvocation) async throws -> ShellResult { try await local.run(invocation) }
    func runStreaming(_ invocation: GitInvocation, onStderr: @escaping @Sendable (String) -> Void) async throws -> ShellResult {
        try await local.runStreaming(invocation, onStderr: onStderr)
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
