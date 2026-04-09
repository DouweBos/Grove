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
    var isLoading = false
    var errorMessage: String?

    /// Untracked change count shown on the Working Copy badge.
    var workingCopyBadgeCount: Int = 0

    // MARK: - Pinned Branches

    /// Branch names that are pinned to the top of the sidebar.
    var pinnedBranchNames: Set<String> = []

    /// Local branches whose names appear in ``pinnedBranchNames``, sorted alphabetically.
    var pinnedBranches: [BranchInfo] {
        localBranches
            .filter { pinnedBranchNames.contains($0.name) }
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

    // MARK: - Dependencies

    let repository: any GitRepositoryProtocol

    // MARK: - Private

    private var pinnedBranchesDefaultsKey: String {
        "grove.pinnedBranches.\(repository.path.path)"
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

        let (local, remote, tagList, remoteList, statusList) = await (lb, rb, tg, rm, st)

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
        do {
            try await repository.checkout(branch: branch.name)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteBranch(_ branch: BranchInfo) async {
        do {
            try await repository.deleteBranch(name: branch.name, force: false)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Merges `branch` into the current HEAD.
    func merge(branch: BranchInfo) async {
        do {
            try await repository.merge(branch: branch.name)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Rebases the current HEAD onto `branch`.
    func rebase(onto branch: BranchInfo) async {
        do {
            try await repository.rebase(onto: branch.name)
            await refresh()
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
            await refresh()
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
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a tag.
    func deleteTag(_ tag: TagInfo) async {
        do {
            try await repository.deleteTag(name: tag.name)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a remote-tracking branch on the remote.
    func deleteRemoteBranch(_ branch: BranchInfo) async {
        guard let remote = branch.remoteName else { return }
        let branchName: String = {
            if branch.name.hasPrefix(remote + "/") {
                return String(branch.name.dropFirst(remote.count + 1))
            }
            return branch.name
        }()
        do {
            try await repository.deleteRemoteBranch(name: branchName, remote: remote)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Updates a submodule at the given path.
    func updateSubmodule(path: String) async {
        do {
            try await repository.updateSubmodule(path: path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Removes a linked worktree.
    func removeWorktree(path: String) async {
        do {
            try await repository.removeWorktree(path: path, force: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Derived

    /// Branches considered "archived" — not HEAD, not ahead of upstream, and
    /// therefore fully merged (or simply stale with no unpushed commits).
    var archivedBranches: [BranchInfo] {
        localBranches.filter { branch in
            !branch.isHEAD && branch.ahead == 0
        }
    }

    /// Active local branches — HEAD or branches that have commits not yet pushed.
    var activeBranches: [BranchInfo] {
        localBranches.filter { branch in
            branch.isHEAD || branch.ahead > 0
        }
    }

    /// Branch groups derived from "/" in branch names.
    var localBranchGroups: [(prefix: String?, branches: [BranchInfo])] {
        var ungrouped: [BranchInfo] = []
        var groups: [String: [BranchInfo]] = [:]

        for branch in localBranches {
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
