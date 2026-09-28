// Domain/RepositoryRefs.swift
// Grove
//
// One read of a repository's refs per refresh, shared by the sidebar, every history list, dialogs and quick actions.

import Foundation
import Observation

/// Branches, tags, remotes and worktrees of one repository, kept until the next refresh replaces them.
@MainActor
@Observable
final class RepositoryRefs {

    private(set) var localBranches: [BranchInfo] = []
    private(set) var remoteBranches: [BranchInfo] = []
    private(set) var tags: [TagInfo] = []
    private(set) var remotes: [RemoteInfo] = []
    private(set) var worktrees: [WorktreeInfo] = []
    private(set) var submodules: [SubmoduleInfo] = []
    /// Parent branch recorded when a branch was created, keyed by branch name.
    private(set) var parents: [String: String] = [:]
    /// Staged or unstaged entries, for the Changes badge.
    private(set) var changedCount = 0
    private(set) var hasLoaded = false
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    /// Bumped whenever branches or tags change, so consumers can skip re-indexing identical refs.
    private(set) var generation = 0

    var headBranch: BranchInfo? { localBranches.first(where: \.isHEAD) }

    let repository: any GitRepositoryProtocol
    /// Off in a session, whose Changes list already reads status; two concurrent reads contend for the index.
    private let readsStatus: Bool
    private var inFlight: Task<Void, Never>?

    init(repository: any GitRepositoryProtocol, readsStatus: Bool = true) {
        self.repository = repository
        self.readsStatus = readsStatus
    }

    /// Re-reads everything concurrently; a call during a running read waits for that read instead of starting another.
    func refresh() async {
        await beginRefresh().value
    }

    /// Starts (or joins) a read synchronously, so lists refreshing alongside it can `settled()` on it.
    @discardableResult
    func beginRefresh() -> Task<Void, Never> {
        if let inFlight { return inFlight }
        let task = Task {
            await read()
            inFlight = nil
        }
        inFlight = task
        return task
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return await settled() }
        await refresh()
    }

    /// The running read's result if one is underway, else the last one; never starts a read once loaded.
    func settled() async {
        if let inFlight { await inFlight.value } else if !hasLoaded { await refresh() }
    }

    func dismissError() { errorMessage = nil }

    /// Replaces the lists directly, for previews and tests.
    func replace(localBranches: [BranchInfo]? = nil, remoteBranches: [BranchInfo]? = nil, tags: [TagInfo]? = nil,
                 remotes: [RemoteInfo]? = nil, worktrees: [WorktreeInfo]? = nil) {
        apply(local: localBranches, remote: remoteBranches, tags: tags)
        if let remotes { self.remotes = remotes }
        if let worktrees { self.worktrees = worktrees }
        hasLoaded = true
    }

    private func read() async {
        isRefreshing = true
        defer { isRefreshing = false }
        readError = nil
        // Each source is read on its own so one failure doesn't hide the others.
        async let local = attempt { try await repository.localBranches() }
        async let remote = attempt { try await repository.remoteBranches() }
        async let tagList = attempt { try await repository.tags() }
        async let remoteList = attempt { try await repository.remotes() }
        async let status = readsStatus ? attempt { try await repository.status() } : nil
        async let worktreeList = attempt { try await repository.worktrees() }
        async let submoduleList = attempt { try await repository.submodules() }
        async let parentMap = attempt { try await repository.branchParents() }
        let (locals, remoteRefs, tagRefs) = await (local, remote, tagList)
        let (newRemotes, entries, newWorktrees, newSubmodules) = await (remoteList, status, worktreeList, submoduleList)

        apply(local: locals, remote: remoteRefs, tags: tagRefs)
        if let newRemotes, newRemotes != remotes { remotes = newRemotes }
        if let newWorktrees, newWorktrees != worktrees { worktrees = newWorktrees }
        if let newSubmodules, newSubmodules != submodules { submodules = newSubmodules }
        if let newParents = await parentMap, newParents != parents { parents = newParents }
        if let entries {
            changedCount = entries.filter { $0.indexStatus != .unmodified || $0.workdirStatus != .unmodified }.count
        }
        errorMessage = readError
        hasLoaded = true
    }

    private var readError: String?

    private func attempt<T>(_ body: @Sendable () async throws -> T) async -> T? {
        do { return try await body() } catch {
            readError = readError ?? error.localizedDescription
            return nil
        }
    }

    /// Assigns only what changed: thousands of tags re-render and re-index every list that shows them.
    private func apply(local: [BranchInfo]?, remote: [BranchInfo]?, tags newTags: [TagInfo]?) {
        var changed = false
        if let local, local != localBranches { localBranches = local; changed = true }
        if let remote, remote != remoteBranches { remoteBranches = remote; changed = true }
        if let newTags, newTags != tags { tags = newTags; changed = true }
        if changed { generation += 1 }
    }
}
