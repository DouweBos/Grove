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
    /// Open and merged pull requests keyed by head branch; a network read, so refreshed at most once a minute.
    private(set) var branchPullRequests: [String: BranchPullRequest] = [:]
    /// Recently merged pull requests, which tell a stack its parent landed.
    private(set) var mergedPullRequests: [BranchPullRequest] = []
    private var pullRequestsFetchedAt: Date?
    private var pullRequestTask: Task<Void, Never>?
    /// Staged or unstaged entries, for the Changes badge.
    private(set) var changedCount = 0
    private(set) var hasLoaded = false
    private(set) var isRefreshing = false
    private(set) var errorMessage: String?
    /// Bumped whenever branches or tags change, so consumers can skip re-indexing identical refs.
    private(set) var generation = 0
    /// Stacked branches recognized from the graph, reflogs and pull requests after each read.
    private(set) var stacks: [BranchStack] = []
    /// Branches whose patches all exist on another branch.
    private(set) var duplicateBranches: [DuplicateBranch] = []
    /// The branch stacks are measured against.
    private(set) var trunk: String?
    private let stackReader = StackReader()
    private var stackTask: Task<Void, Never>?
    private var needsStackRead = false

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
        refreshPullRequests()
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

    /// The pull request whose head is `branch`; remote branches match on the part after the remote name.
    func pullRequest(for branch: BranchInfo) -> BranchPullRequest? {
        let head = branch.isRemote ? branch.name.split(separator: "/", maxSplits: 1).last.map(String.init) : branch.name
        return head.flatMap { branchPullRequests[$0] }.flatMap { $0.applies(toTip: branch.targetSHA) ? $0 : nil }
    }

    func hasOpenPullRequest(branch name: String) -> Bool {
        branchPullRequests[name].map { !$0.isMerged } ?? false
    }

    /// Open pull requests keyed by head branch, which is what stacks are read from.
    private var openPullRequests: [String: BranchPullRequest] { branchPullRequests.filter { !$0.value.isMerged } }

    /// Reads pull requests again right away and waits for them, e.g. after changing one on the host.
    func refreshPullRequestsNow() async {
        if let pullRequestTask { await pullRequestTask.value }
        refreshPullRequests(force: true)
        await pullRequestTask?.value
    }

    /// Runs beside ref reads without holding them up; a failure (no account, no hosted remote) keeps the last result.
    func refreshPullRequests(force: Bool = false) {
        guard pullRequestTask == nil else { return }
        if !force, let pullRequestsFetchedAt, Date().timeIntervalSince(pullRequestsFetchedAt) < 60 { return }
        pullRequestTask = Task {
            if let fetched = try? await repository.branchPullRequests() {
                let indexed = BranchPullRequest.index(fetched)
                let merged = fetched.filter(\.isMerged)
                if indexed != branchPullRequests { branchPullRequests = indexed }
                if merged != mergedPullRequests { mergedPullRequests = merged }
                pullRequestsLoaded = true
            }
            pullRequestsFetchedAt = Date()
            pullRequestTask = nil
            if hasLoaded { await readStacks() }
        }
    }

    /// Replaces the lists directly, for previews and tests.
    func replace(localBranches: [BranchInfo]? = nil, remoteBranches: [BranchInfo]? = nil, tags: [TagInfo]? = nil,
                 remotes: [RemoteInfo]? = nil, worktrees: [WorktreeInfo]? = nil, stacks: [BranchStack]? = nil) {
        apply(local: localBranches, remote: remoteBranches, tags: tags)
        if let remotes { self.remotes = remotes }
        if let worktrees { self.worktrees = worktrees }
        if let stacks {
            self.stacks = stacks
            trunk = stacks.first?.trunk
        }
        hasLoaded = true
    }

    /// The stack `branch` is a layer of.
    func stack(containing branch: String) -> BranchStack? {
        stacks.first { $0.contains(branch) }
    }

    /// Recognizes stacks from what was just read; a read during a running one runs again after it.
    func readStacks() async {
        if let stackTask {
            needsStackRead = true
            return await stackTask.value
        }
        let task = Task {
            repeat {
                needsStackRead = false
                let snapshot = StackReader.Snapshot(
                    localBranches: localBranches, remoteBranches: remoteBranches, remotes: remotes, worktrees: worktrees,
                    openPullRequests: openPullRequests, mergedPullRequests: mergedPullRequests,
                    pullRequestsLoaded: pullRequestsLoaded)
                if let result = await stackReader.read(snapshot, repository: repository) {
                    stacks = result.stacks
                    duplicateBranches = result.duplicates
                }
                trunk = stackReader.trunk
            } while needsStackRead
            stackTask = nil
        }
        stackTask = task
        await task.value
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
        await readStacks()
    }

    private var readError: String?
    private var pullRequestsLoaded = false

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
