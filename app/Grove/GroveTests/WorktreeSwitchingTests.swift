// WorktreeSwitchingTests.swift
// GroveTests
//
// A repository window runs git in one worktree at a time; double-clicking another worktree opens it in a new tab.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct WorktreeSwitchingTests {

    private let mainPath = "/Users/dev/Projects/my-app"
    private var linkedPath: String { mainPath + "-feature-auth" }

    @Test func branchCheckedOutElsewhereOpensItsWorktreeInANewTab() async throws {
        let vm = SidebarViewModel(repository: MockGitRepository(path: URL(fileURLWithPath: mainPath)))
        await vm.refresh()
        var openedInTab: String?
        var switched = false
        vm.onOpenWorktreeInNewTab = { openedInTab = $0 }
        vm.onSwitchWorktree = { _ in switched = true }
        let branch = try #require(vm.localBranches.first { $0.name == "feature/auth" })

        #expect(vm.actions.worktree(checkingOut: branch)?.path == linkedPath)
        await vm.activate(branch: branch)
        #expect(openedInTab == linkedPath)
        #expect(!switched)
    }

    @Test func currentWorktreeIsNotOpenedInANewTab() async {
        let vm = SidebarViewModel(repository: MockGitRepository(path: URL(fileURLWithPath: mainPath)))
        await vm.refresh()
        var opened = false
        vm.onOpenWorktreeInNewTab = { _ in opened = true }
        if let current = vm.worktrees.first(where: vm.actions.isCurrent) { vm.openInNewTab(current) }
        #expect(!opened)
    }

    @Test func currentWorktreeIsNotOfferedAsATarget() async {
        let vm = SidebarViewModel(repository: MockGitRepository(path: URL(fileURLWithPath: mainPath)))
        await vm.refresh()
        #expect(vm.actions.otherWorktrees.map(\.path) == [linkedPath])
        var switched = false
        vm.onSwitchWorktree = { _ in switched = true }
        if let current = vm.worktrees.first(where: vm.actions.isCurrent) { vm.switchTo(current) }
        #expect(!switched)
    }

    @Test func switchingPausesTheOldSessionAndKeepsTheTab() async throws {
        let window = WindowViewModel(manager: MockRepositoryManager())
        window.openReference(RepositoryReference(path: mainPath))
        window.loadSessionIfNeeded(for: RepositoryReference(path: mainPath))
        let first = try await session(in: window, at: mainPath)
        first.restoreSelection(.stashes)

        first.sidebarVM.onSwitchWorktree?(linkedPath)
        #expect(window.openRepo?.path == linkedPath)
        #expect(window.sessions[mainPath]?.session.isActive == false)

        window.loadSessionIfNeeded(for: RepositoryReference(path: linkedPath))
        let second = try await session(in: window, at: linkedPath)
        #expect(second.selectedItem == .stashes)
    }

    private func session(in window: WindowViewModel, at path: String) async throws -> RepositorySession {
        for _ in 0..<50 {
            if let loaded = window.sessions[path] { return loaded.session }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw CancellationError()
    }
}
