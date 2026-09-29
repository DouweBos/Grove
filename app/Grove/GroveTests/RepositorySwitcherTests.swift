// RepositorySwitcherTests.swift
// GroveTests
//
// The sidebar title's switcher lists repositories, the open one first, and switches on the same tab.

import Foundation
import Testing
@testable import Grove

@MainActor
struct RepositorySwitcherTests {

    private let myApp = "/Users/dev/Projects/my-app"
    private let apiServer = "/Users/dev/Projects/api-server"

    @Test func openRepositoryComesFirstThenMostRecent() {
        let window = WindowViewModel(manager: MockRepositoryManager())
        window.openReference(RepositoryReference(path: apiServer))
        #expect(window.repositorySwitcherItems(matching: "").map(\.displayName)
                == ["api-server", "my-app", "blog", "dotfiles", "design-system"])
    }

    @Test func nameMatchesAtTheStartRankFirst() {
        let window = WindowViewModel(manager: MockRepositoryManager())
        window.openReference(RepositoryReference(path: myApp))
        #expect(window.repositorySwitcherItems(matching: "a").map(\.displayName) == ["api-server", "my-app"])
        #expect(window.repositorySwitcherItems(matching: "SERVER").map(\.displayName) == ["api-server"])
        #expect(window.repositorySwitcherItems(matching: "nope").isEmpty)
    }

    @Test func switchingKeepsTheTabAndClosesTheSwitcher() async throws {
        let window = WindowViewModel(manager: MockRepositoryManager())
        window.openReference(RepositoryReference(path: myApp))
        window.loadSessionIfNeeded(for: RepositoryReference(path: myApp))
        let first = try await session(in: window, at: myApp)
        first.restoreSelection(.stashes)
        window.showRepositorySwitcher()

        let target = try #require(window.repositorySwitcherItems(matching: "api").first)
        window.switchRepository(to: target)
        #expect(!window.isShowingRepositorySwitcher)
        #expect(window.openRepo?.path == apiServer)
        #expect(window.sessions[myApp]?.session.isActive == false)

        window.loadSessionIfNeeded(for: RepositoryReference(path: apiServer))
        let second = try await session(in: window, at: apiServer)
        #expect(second.selectedItem == .stashes)
    }

    @Test func switcherOnlyOpensInsideARepository() {
        let window = WindowViewModel(manager: MockRepositoryManager())
        #expect(window.handleBrowserAction(.switchRepository))
        #expect(!window.isShowingRepositorySwitcher)
    }

    @Test func nestedWorktreesAreLeftToTheWorktreeSwitcher() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grove-switcher-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repo = root.appendingPathComponent("main").path, worktree = root.appendingPathComponent("wt").path
        try git(["init", "-q", "-b", "main", repo], in: root.path)
        try git(["-c", "user.name=T", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"], in: repo)
        try git(["worktree", "add", "-q", "-b", "feature", worktree], in: repo)

        let manager = MockRepositoryManager()
        try manager.addBookmark(path: repo, displayName: "main", groupID: nil)
        try manager.addBookmark(path: worktree, displayName: "wt", groupID: nil)
        let window = WindowViewModel(manager: manager)
        window.openReference(RepositoryReference(path: worktree))
        window.showRepositorySwitcher()

        let items = window.repositorySwitcherItems(matching: "")
        #expect(!items.contains { $0.path == worktree })
        #expect(items.first?.path == repo)
        #expect(window.currentBookmarkPath == repo)
    }

    private func git(_ args: [String], in directory: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.executableLoad) }
    }

    private func session(in window: WindowViewModel, at path: String) async throws -> RepositorySession {
        for _ in 0..<50 {
            if let loaded = window.sessions[path] { return loaded.session }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw CancellationError()
    }
}
