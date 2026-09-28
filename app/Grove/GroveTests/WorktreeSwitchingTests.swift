// WorktreeSwitchingTests.swift
// GroveTests
//
// A repository window runs git in one worktree at a time; branches and worktree rows switch it.

import Foundation
import Testing
@testable import Grove

@MainActor
struct WorktreeSwitchingTests {

    private let mainPath = "/Users/dev/Projects/my-app"
    private var linkedPath: String { mainPath + "-feature-auth" }

    @Test func branchCheckedOutElsewhereSwitchesInsteadOfCheckingOut() async throws {
        let vm = SidebarViewModel(repository: MockGitRepository(path: URL(fileURLWithPath: mainPath)))
        await vm.refresh()
        var switchedTo: String?
        vm.onSwitchWorktree = { switchedTo = $0 }
        let branch = try #require(vm.localBranches.first { $0.name == "feature/auth" })

        #expect(vm.worktree(checkingOut: branch)?.path == linkedPath)
        await vm.activate(branch: branch)
        #expect(switchedTo == linkedPath)
    }

    @Test func currentWorktreeIsNotOfferedAsATarget() async {
        let vm = SidebarViewModel(repository: MockGitRepository(path: URL(fileURLWithPath: mainPath)))
        await vm.refresh()
        #expect(vm.otherWorktrees.map(\.path) == [linkedPath])
        var switched = false
        vm.onSwitchWorktree = { _ in switched = true }
        if let current = vm.worktrees.first(where: vm.isCurrent) { vm.switchTo(current) }
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
