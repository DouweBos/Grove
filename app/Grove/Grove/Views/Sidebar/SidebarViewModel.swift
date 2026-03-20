// Views/Sidebar/SidebarViewModel.swift
// Grove

import Foundation
import Observation

/// ViewModel for the in-repository sidebar.
///
/// Manages branch, remote, tag lists and the current navigation selection.
@Observable
final class SidebarViewModel {

    // MARK: - State

    var selection: SidebarItem? = .history
    var localBranches: [BranchInfo] = []
    var remoteBranches: [BranchInfo] = []
    var tags: [TagInfo] = []
    var remotes: [RemoteInfo] = []
    var isLoading = false
    var errorMessage: String?

    /// Untracked change count shown on the Working Copy badge.
    var workingCopyBadgeCount: Int = 0

    // MARK: - Dependencies

    let repository: any GitRepositoryProtocol

    // MARK: - Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Actions

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let lb = repository.localBranches()
            async let rb = repository.remoteBranches()
            async let tg = repository.tags()
            async let rm = repository.remotes()
            async let st = repository.status()
            let (local, remote, tagList, remoteList, statusList) = try await (lb, rb, tg, rm, st)
            localBranches = local
            remoteBranches = remote
            tags = tagList
            remotes = remoteList
            workingCopyBadgeCount = statusList.filter {
                $0.indexStatus != .unmodified || $0.workdirStatus != .unmodified
            }.count
        } catch {
            errorMessage = error.localizedDescription
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

    // MARK: - Derived

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
