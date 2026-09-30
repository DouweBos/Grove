// RepositorySessionTests.swift
// GroveTests
//
// Large repositories are slow to re-read, so sessions stay cached, refs are read once per refresh,
// and hidden lists reload only when shown.

import Foundation
import Testing
@testable import Grove

@MainActor
struct RepositorySessionTests {

    // MARK: - Session cache

    @Test func leavingPausesTheSessionAndReturningReusesIt() async throws {
        let window = WindowViewModel(manager: MockRepositoryManager())
        let first = try await open("/tmp/grove-tests/alpha", in: window)
        try await waitUntil { first.isActive }

        window.closeRepository()
        #expect(!first.isActive)
        #expect(window.sessions["/tmp/grove-tests/alpha"]?.session === first)

        let again = try await open("/tmp/grove-tests/alpha", in: window)
        #expect(again === first)
        try await waitUntil { first.isActive }
    }

    @Test func pausedSessionsStopWatchingButKeepFetching() async throws {
        let window = WindowViewModel(manager: MockRepositoryManager())
        let first = try await open("/tmp/grove-tests/alpha", in: window)
        try await waitUntil { first.isActive }
        #expect(first.autoFetcher.isStarted)

        // Opening another repository pauses the one that was open; it keeps fetching in the background.
        let second = try await open("/tmp/grove-tests/beta", in: window)
        #expect(!first.isActive && first.autoFetcher.isStarted)
        try await waitUntil { second.isActive }
    }

    @Test func onlyTheMostRecentSessionsAreKept() async throws {
        let window = WindowViewModel(manager: MockRepositoryManager())
        let paths = (0...WindowViewModel.cachedSessionLimit).map { "/tmp/grove-tests/repo\($0)" }
        for path in paths { try await open(path, in: window) }

        #expect(window.sessions.count == WindowViewModel.cachedSessionLimit)
        #expect(window.sessions[paths[0]] == nil)
        #expect(window.sessions[paths.last!] != nil)
    }

    // MARK: - Shared refs

    @Test func refreshAllReadsRefsOnceForEveryList() async {
        let repo = MockGitRepository()
        let session = RepositorySession(repository: repo)
        await session.refs.refresh()
        await session.historyVM.loadInitial()
        for name in ["main", "develop"] { await session.filteredHistoryVM(for: name).loadInitial() }
        session.restoreSelection(.history)
        let before = repo.callCounts

        await session.refreshAll()

        #expect(delta("tags()", repo, before) == 1)
        #expect(delta("localBranches()", repo, before) == 1)
        #expect(delta("remoteBranches()", repo, before) == 1)
        #expect(session.historyVM.tags == session.refs.tags)
        #expect(session.sidebarVM.localBranches == session.refs.localBranches)
    }

    @Test func dialogsOpenAtOnceFromCachedRefs() async {
        let repo = MockGitRepository()
        let session = RepositorySession(repository: repo)
        await session.refs.refresh()
        let before = repo.callCounts

        session.handleAction(.pull)
        session.handleAction(.merge)

        #expect(session.toolbarState.isPullPresented && session.toolbarState.isMergePresented)
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(delta("remoteBranches()", repo, before) == 0)
        #expect(delta("localBranches()", repo, before) == 0)
    }

    // MARK: - Hidden lists

    @Test func hiddenHistoryListsReloadWhenShownAgain() async {
        let repo = MockGitRepository()
        let session = RepositorySession(repository: repo)
        let filtered = session.filteredHistoryVM(for: "develop")
        await filtered.loadInitial()

        await session.refreshAll()
        #expect(filtered.isStale)

        let before = repo.callCounts
        await filtered.loadIfNeeded()
        #expect(delta("log(maxCount:skip:branch:)", repo, before) == 1)
        #expect(!filtered.isStale)
    }

    @Test func filteredHistoryListsAreCapped() {
        let session = RepositorySession(repository: MockGitRepository())
        let names = (0...RepositorySession.filteredHistoryLimit).map { "branch-\($0)" }
        for name in names { _ = session.filteredHistoryVM(for: name) }

        #expect(session.filteredHistoryVMs.count == RepositorySession.filteredHistoryLimit)
        #expect(session.filteredHistoryVMs[names[0]] == nil)
    }

    @Test func revisitingATabDoesNotReReadIt() async {
        let repo = MockGitRepository()
        let session = RepositorySession(repository: repo)
        await session.refreshOnEntry(.reflog)
        await session.refreshOnEntry(.reflog)
        #expect(repo.callCounts["reflog(maxCount:)"] == 1)

        // A change while the tab is hidden makes the next visit read it again.
        await session.refreshAll()
        await session.refreshOnEntry(.reflog)
        #expect(repo.callCounts["reflog(maxCount:)"] == 2)
    }

    @Test func branchesReviewUsesTheSharedRefs() async {
        let repo = MockGitRepository()
        let session = RepositorySession(repository: repo)
        session.restoreSelection(.branchesReview)
        let before = repo.callCounts

        await session.refreshAll()

        #expect(delta("localBranches()", repo, before) == 1)
        #expect(!session.branchesReviewVM.branches.isEmpty)
    }

    @Test func pullRequestsReReadOnlyAfterTheirLifetime() async {
        let repo = MockGitRepository()
        let session = RepositorySession(repository: repo)
        await session.refreshOnEntry(.pullRequests)
        #expect(!session.needsRefresh(.pullRequests))

        await session.refreshAll()
        #expect(!session.needsRefresh(.pullRequests))
        session.tabRefreshes[.pullRequests] = TabRefresh(generation: 0, date: .distantPast)
        #expect(session.needsRefresh(.pullRequests))
    }

    @Test func actionsReReadOnlyAfterTheirLifetime() async {
        let repo = MockGitRepository()
        let session = RepositorySession(repository: repo)
        session.handleAction(.navigateCI)
        #expect(session.sidebarVM.selection == .ci && RepositoryTab(item: .ci) == .ci)

        await session.refreshOnEntry(.ci)
        #expect(!session.needsRefresh(.ci) && repo.ci.queries.count == 1)

        // A local change can't move what the host reports, so a refresh neither re-reads nor expires the list.
        session.restoreSelection(.ci)
        await session.refreshAll()
        #expect(!session.needsRefresh(.ci) && repo.ci.queries.count == 1)
        session.tabRefreshes[.ci] = TabRefresh(generation: 0, date: .distantPast)
        #expect(session.needsRefresh(.ci))
    }

    @Test func reloadDuringALoadRunsAfterIt() async throws {
        let repo = MockGitRepository()
        let vm = HistoryViewModel(repository: repo)
        await vm.loadInitial()
        let before = repo.callCounts

        async let first: Void = vm.reload()
        async let second: Void = vm.reload()
        _ = await (first, second)
        try await waitUntil { delta("log(maxCount:skip:branch:)", repo, before) == 2 && !vm.isLoading }
    }

    // MARK: - Helpers

    private func delta(_ call: String, _ repo: MockGitRepository, _ before: [String: Int]) -> Int {
        (repo.callCounts[call] ?? 0) - (before[call] ?? 0)
    }

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

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<60 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(condition())
    }
}
