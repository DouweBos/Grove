// Views/Sidebar/SidebarViewModel.swift
// Grove

import Foundation
import Observation

/// ViewModel for the in-repository sidebar.
///
/// Manages branch, remote, tag lists and the current navigation selection.
@MainActor
@Observable
final class SidebarViewModel {

    // MARK: - State

    var selection: SidebarItem? = .workingCopy
    var localBranches: [BranchInfo] = []
    var remoteBranches: [BranchInfo] = []
    var tags: [TagInfo] = []
    var remotes: [RemoteInfo] = []
    var worktrees: [WorktreeInfo] = []
    var submodules: [SubmoduleInfo] = []
    var isLoading = false
    var errorMessage: String?

    /// Untracked change count shown on the Working Copy badge.
    var workingCopyBadgeCount: Int = 0

    /// Worktrees other than the one this window shows; from a linked worktree that includes the main one.
    var otherWorktrees: [WorktreeInfo] {
        let current = repository.path.standardizedFileURL.resolvingSymlinksInPath().path
        return worktrees.filter { URL(fileURLWithPath: $0.path).standardizedFileURL.resolvingSymlinksInPath().path != current }
    }

    func select(_ item: SidebarItem) {
        selection = item
    }

    /// Dropping on Changes: `stash@{N}` applies a stash, a SHA cherry-picks,
    /// a branch merges (or rebases when `rebase` is set, i.e. Option held).
    func handleWorkingCopyDrop(_ payload: String, rebase: Bool) -> Bool {
        if payload.hasPrefix("stash@{"), payload.hasSuffix("}"),
           let index = Int(payload.dropFirst("stash@{".count).dropLast()) {
            Task { await stashApply(index: index) }
            return true
        }
        let isHex = payload.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
        if isHex && payload.count >= 7 {
            Task { await cherryPick(sha: payload) }
            return true
        }
        guard let branch = localBranches.first(where: { $0.name == payload }) else { return false }
        Task {
            if rebase { await self.rebase(onto: branch) } else { await merge(branch: branch) }
        }
        return true
    }

    // MARK: - Pinned Branches

    /// Branch names that are pinned to the top of the sidebar.
    var pinnedBranchNames: Set<String> = []

    /// Local branches whose names appear in ``pinnedBranchNames``, sorted alphabetically.
    var pinnedBranches: [BranchInfo] {
        localBranches
            .filter { pinnedBranchNames.contains($0.name) && !archivedBranchNames.contains($0.name) }
            .sorted { $0.name < $1.name }
    }

    /// Toggle a branch between pinned and unpinned.
    func togglePin(branch: BranchInfo) {
        if pinnedBranchNames.contains(branch.name) {
            pinnedBranchNames.remove(branch.name)
        } else {
            pinnedBranchNames.insert(branch.name)
        }
        savePinnedBranches()
    }

    // MARK: - Archived Branches

    /// Branches the user archived: hidden from Branches, listed under Archived.
    var archivedBranchNames: Set<String> = []

    var archivedBranches: [BranchInfo] {
        localBranches.filter { archivedBranchNames.contains($0.name) }.sorted { $0.name < $1.name }
    }

    func archive(branch: BranchInfo) {
        archivedBranchNames.insert(branch.name)
        pinnedBranchNames.remove(branch.name)
        UserDefaults.standard.set(Array(archivedBranchNames), forKey: archivedBranchesDefaultsKey)
        savePinnedBranches()
    }

    func unarchive(branch: BranchInfo) {
        archivedBranchNames.remove(branch.name)
        UserDefaults.standard.set(Array(archivedBranchNames), forKey: archivedBranchesDefaultsKey)
    }

    // MARK: - Dependencies

    let repository: any GitRepositoryProtocol

    /// Set by the session so a sidebar mutation refreshes every view, not just the sidebar.
    var onRepositoryChanged: (() async -> Void)?
    var undoManager: GitUndoManager?

    /// Call after anything that changed refs or the working tree.
    func didChangeRepository() async {
        if let onRepositoryChanged { await onRepositoryChanged() } else { await refresh() }
    }

    func dismissError() { errorMessage = nil }

    // MARK: - Private

    private var pinnedBranchesDefaultsKey: String {
        "grove.pinnedBranches.\(repository.path.path)"
    }

    private var archivedBranchesDefaultsKey: String {
        "grove.archivedBranches.\(repository.path.path)"
    }

    // MARK: - Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
        loadPinnedBranches()
    }

    // MARK: - Pinned Branches Persistence

    private func loadPinnedBranches() {
        let saved = UserDefaults.standard.stringArray(forKey: pinnedBranchesDefaultsKey) ?? []
        pinnedBranchNames = Set(saved)
        archivedBranchNames = Set(UserDefaults.standard.stringArray(forKey: archivedBranchesDefaultsKey) ?? [])
    }

    private func savePinnedBranches() {
        UserDefaults.standard.set(Array(pinnedBranchNames), forKey: pinnedBranchesDefaultsKey)
    }

    // MARK: - Actions

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Fetch each data source concurrently. Each call is wrapped so
        // one failure doesn't prevent the others from loading.
        async let lb: [BranchInfo]? = tryOrNil { try await repository.localBranches() }
        async let rb: [BranchInfo]? = tryOrNil { try await repository.remoteBranches() }
        async let tg: [TagInfo]? = tryOrNil { try await repository.tags() }
        async let rm: [RemoteInfo]? = tryOrNil { try await repository.remotes() }
        async let st: [StatusEntry]? = tryOrNil { try await repository.status() }
        async let wt: [WorktreeInfo]? = tryOrNil { try await repository.worktrees() }
        async let sm: [SubmoduleInfo]? = tryOrNil { try await repository.submodules() }

        let (local, remote, tagList, remoteList, statusList) = await (lb, rb, tg, rm, st)
        let (worktreeList, submoduleList) = await (wt, sm)
        if let worktreeList { worktrees = worktreeList }
        if let submoduleList { submodules = submoduleList }

        if let local { localBranches = local }
        if let remote { remoteBranches = remote }
        if let tagList { tags = tagList }
        if let remoteList { remotes = remoteList }
        if let statusList {
            workingCopyBadgeCount = statusList.filter {
                $0.indexStatus != .unmodified || $0.workdirStatus != .unmodified
            }.count
        }
    }

    /// Run an async throwing closure, returning `nil` on error.
    private func tryOrNil<T>(_ body: @Sendable () async throws -> T) async -> T? {
        do { return try await body() }
        catch {
            errorMessage = errorMessage ?? error.localizedDescription
            return nil
        }
    }

    func checkout(branch: BranchInfo) async {
        let previous = localBranches.first(where: \.isHEAD)?.name
        do {
            try await repository.checkout(branch: branch.name)
            recordCheckout(of: branch.name, from: previous)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Checks out a remote branch as a local tracking branch (git's DWIM),
    /// or the existing local branch of the same name.
    func checkout(remoteBranch branch: BranchInfo) async {
        let localName = Self.shortName(of: branch)
        let previous = localBranches.first(where: \.isHEAD)?.name
        do {
            try await repository.checkout(branch: localName)
            recordCheckout(of: localName, from: previous)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteBranch(_ branch: BranchInfo, force: Bool = false) async {
        do {
            try await repository.deleteBranch(name: branch.name, force: force)
            recordBranchDeletion(branch)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Detached HEAD has no branch to return to, so it isn't recorded.
    private func recordCheckout(of target: String, from previous: String?) {
        guard let previous, previous != target else { return }
        undoManager?.record(GitUndoManager.checkoutAction(targetBranch: target, previousBranch: previous,
                                                          repository: repository))
    }

    /// Also called by the delete dialog, which deletes the branch itself.
    func recordBranchDeletion(_ branch: BranchInfo) {
        undoManager?.record(GitUndoManager.deleteBranchAction(branchName: branch.name, sha: branch.targetSHA,
                                                              repository: repository))
    }

    /// Merges `branch` into the current HEAD.
    func merge(branch: BranchInfo) async {
        do {
            try await repository.merge(branch: branch.name)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Rebases the current HEAD onto `branch`.
    func rebase(onto branch: BranchInfo) async {
        do {
            try await repository.rebase(onto: branch.name)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Cherry-picks the commit identified by `sha` onto HEAD.
    ///
    /// Called when a commit SHA is dropped onto the Working Copy sidebar item.
    func cherryPick(sha: String) async {
        do {
            try await repository.cherryPick(commit: sha)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Applies the stash at `index` without dropping it from the stash list.
    ///
    /// Called when a stash entry is dropped onto the Working Copy sidebar item.
    func stashApply(index: Int) async {
        do {
            try await repository.stashApply(index: index, drop: false)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a tag.
    func deleteTag(_ tag: TagInfo) async {
        do {
            try await repository.deleteTag(name: tag.name)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a remote-tracking branch on the remote.
    func deleteRemoteBranch(_ branch: BranchInfo) async {
        guard let remote = branch.remoteName else { return }
        do {
            try await repository.deleteRemoteBranch(name: Self.shortName(of: branch), remote: remote)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Updates a submodule at the given path.
    func updateSubmodule(path: String) async {
        do {
            try await repository.updateSubmodule(path: path)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Removes a linked worktree.
    func removeWorktree(path: String) async {
        do {
            try await repository.removeWorktree(path: path, force: false)
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pruneWorktrees() async {
        do {
            try await repository.pruneWorktrees()
            await didChangeRepository()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Derived

    /// Remote branch name without its "remote/" prefix.
    static func shortName(of branch: BranchInfo) -> String {
        if let remote = branch.remoteName, branch.name.hasPrefix(remote + "/") {
            return String(branch.name.dropFirst(remote.count + 1))
        }
        return branch.name
    }

    /// Branch groups derived from "/" in branch names.
    var localBranchGroups: [(prefix: String?, branches: [BranchInfo])] {
        var ungrouped: [BranchInfo] = []
        var groups: [String: [BranchInfo]] = [:]

        for branch in localBranches where !archivedBranchNames.contains(branch.name) {
            if let slashIndex = branch.name.firstIndex(of: "/") {
                let prefix = String(branch.name[branch.name.startIndex..<slashIndex])
                groups[prefix, default: []].append(branch)
            } else {
                ungrouped.append(branch)
            }
        }

        var result: [(prefix: String?, branches: [BranchInfo])] = []
        result.append((prefix: nil, branches: ungrouped))
        for key in groups.keys.sorted() {
            result.append((prefix: key, branches: groups[key]!))
        }
        return result
    }

    /// Remote branches grouped by their remote name.
    var remoteBranchGroups: [String: [BranchInfo]] {
        Dictionary(grouping: remoteBranches) { $0.remoteName ?? "origin" }
    }
}
