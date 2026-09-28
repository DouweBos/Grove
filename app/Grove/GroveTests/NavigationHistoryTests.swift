// NavigationHistoryTests.swift
// GroveTests
//
// Back / forward through the window: browsers, repositories and their tabs.

import Foundation
import Testing
@testable import Grove

@MainActor
struct NavigationHistoryTests {

    private let repoA = "/Users/dev/Projects/alpha"
    private let repoB = "/Users/dev/Projects/beta"

    @Test func backLeavesTheRepositoryAndForwardReturns() async throws {
        let window = WindowViewModel(manager: MockRepositoryManager())
        #expect(!window.canGoBack)
        try await open(repoA, in: window)

        window.goBack()
        #expect(window.isBrowsing && window.browserMode == .local)
        #expect(window.canGoForward)

        window.goForward()
        #expect(window.openRepo?.path == repoA)
    }

    @Test func tabChangesAreStepsWithinTheRepository() async throws {
        let window = WindowViewModel(manager: MockRepositoryManager())
        let session = try await open(repoA, in: window)
        selectTab(.history, in: session, window: window)
        selectTab(.stashes, in: session, window: window)

        window.goBack()
        #expect(session.selectedItem == .history)
        window.goBack()
        #expect(session.selectedItem == .workingCopy)
        window.goBack()
        #expect(window.isBrowsing)
    }

    @Test func backFromALocalCloneReturnsToTheRemoteBrowser() async throws {
        let window = WindowViewModel(manager: MockRepositoryManager())
        window.showRemoteRepositories()
        window.openLocalClone(atPath: repoB)
        #expect(window.openRepo?.path == repoB)

        window.goBack()
        #expect(window.isBrowsing && window.browserMode == .remote)
    }

    @Test func aNewStepClearsForwardHistory() async throws {
        let window = WindowViewModel(manager: MockRepositoryManager())
        try await open(repoA, in: window)
        window.goBack()
        #expect(window.canGoForward)
        window.showRemoteRepositories()
        #expect(!window.canGoForward)
    }

    @Test func repeatingTheSamePlaceAddsNoStep() {
        let window = WindowViewModel(manager: MockRepositoryManager())
        window.showLocalRepositories()
        window.showLocalRepositories()
        #expect(!window.canGoBack)
    }

    // MARK: - Helpers

    @discardableResult
    private func open(_ path: String, in window: WindowViewModel) async throws -> RepositorySession {
        window.openReference(RepositoryReference(path: path))
        window.loadSessionIfNeeded(for: RepositoryReference(path: path))
        for _ in 0..<50 {
            if let loaded = window.sessions[path] { return loaded.session }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw CancellationError()
    }

    /// What RepositoryContentRouter does when the sidebar selection changes.
    private func selectTab(_ item: SidebarItem, in session: RepositorySession, window: WindowViewModel) {
        window.recordNavigation(to: .repository(path: session.repository.path.path, item: item))
        session.restoreSelection(item)
    }
}
