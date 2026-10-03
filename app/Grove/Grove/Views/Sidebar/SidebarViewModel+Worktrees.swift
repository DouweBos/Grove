// Views/Sidebar/SidebarViewModel+Worktrees.swift
// Grove
//
// Removing worktrees, and deleting branches that one has checked out.

import Foundation
import GroveKit

extension SidebarViewModel {

    var mainWorktreePath: String? { worktrees.first(where: \.isMain)?.path }

    /// `git worktree remove`; `force` also discards its uncommitted changes. Throws for the dialog to show.
    func removeWorktree(_ worktree: WorktreeInfo, force: Bool) async throws {
        try await repository.removeWorktree(path: worktree.path, force: force)
        onWorktreeRemoved?(worktree.path, mainWorktreePath)
    }

    /// Removes `worktree`, then deletes `branch` if given; git won't delete a branch a worktree has checked out.
    /// A retry after the branch failed skips the worktree, which is already gone.
    func removeWorktree(_ worktree: WorktreeInfo, force: Bool,
                        deleting branch: BranchInfo?, forceBranch: Bool) async throws {
        if worktrees.contains(where: { $0.path == worktree.path }) {
            try await removeWorktree(worktree, force: force)
        }
        guard let branch else { return }
        try await repository.deleteBranch(name: branch.name, force: forceBranch)
        recordBranchDeletion(branch)
    }

    /// The local branch a worktree has checked out, for offering to delete it along with the worktree.
    func branch(checkedOutIn worktree: WorktreeInfo) -> BranchInfo? {
        guard let name = worktree.branch else { return nil }
        return localBranches.first { $0.name == name }
    }
}
