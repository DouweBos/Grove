// Views/Dialogs/DeleteBranchDialogView.swift
// Grove

import GroveKit
import SwiftUI

/// Confirms deleting a local branch, optionally forcing it, removing its remote counterpart,
/// or first removing the worktree that has it checked out.
struct DeleteBranchDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let viewModel: SidebarViewModel
    let branch: BranchInfo

    @State private var forceDelete = false
    @State private var deleteRemote = false
    @State private var removeWorktree = false
    @State private var discardWorktreeChanges = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    /// Read live, so it clears once the worktree is gone even if deleting the branch then fails.
    private var worktree: WorktreeInfo? { viewModel.actions.worktree(checkingOut: branch) }

    /// "origin" and "feature/x" from an upstream like "origin/feature/x".
    private var upstreamParts: (remote: String, name: String)? {
        guard let upstream = branch.upstreamShortName, let slash = upstream.firstIndex(of: "/") else { return nil }
        return (String(upstream[..<slash]), String(upstream[upstream.index(after: slash)...]))
    }

    private var isBlocked: Bool { branch.isHEAD || (worktree != nil && !removeWorktree) }

    var body: some View {
        DialogSheet(
            title: "Delete \(branch.name)?",
            message: "Removes the local branch. Commits that no other branch contains can only be recovered from the reflog.",
            symbol: "trash",
            width: 440,
            progress: isDeleting ? "Deleting \(branch.name)…" : nil,
            errorMessage: errorMessage,
            primaryTitle: worktree != nil && removeWorktree ? "Remove Worktree and Delete" : "Delete",
            isDestructive: true,
            isPrimaryDisabled: isBlocked,
            onCancel: { dismiss() },
            onPrimary: performDelete
        ) {
            DialogCard {
                DialogOptionRow(
                    isOn: $forceDelete,
                    label: "Delete Even if Unmerged",
                    description: "Required when the branch has commits that aren't merged anywhere."
                )
                if let upstreamParts {
                    DialogOptionRow(
                        isOn: $deleteRemote,
                        label: "Also Delete \(upstreamParts.remote)/\(upstreamParts.name)",
                        description: "Removes the branch on the remote for everyone."
                    )
                }
                if let worktree {
                    DialogOptionRow(
                        isOn: $removeWorktree,
                        label: "Remove Its Worktree First",
                        description: "Deletes the folder \(abbreviatingHome(worktree.path))."
                    )
                    if removeWorktree {
                        DialogOptionRow(
                            isOn: $discardWorktreeChanges,
                            label: "Remove Even with Uncommitted Changes",
                            description: "Discards the worktree's modified and untracked files."
                        )
                    }
                }
            }
            if branch.isHEAD {
                Banner(symbol: "exclamationmark.triangle", message: "You can't delete the checked-out branch. Check out another branch first.")
            } else if let worktree {
                Banner(symbol: "tree",
                       message: "Checked out in the worktree at \(abbreviatingHome(worktree.path)). Git can't delete it while it's checked out there.",
                       actionTitle: "Open Worktree",
                       action: {
                           viewModel.openInNewTab(worktree)
                           dismiss()
                       })
            }
        }
    }

    private func performDelete() {
        isDeleting = true
        errorMessage = nil
        Task {
            do {
                if let worktree, removeWorktree {
                    try await viewModel.actions.removeWorktree(worktree, force: discardWorktreeChanges,
                                                       deleting: branch, forceBranch: forceDelete)
                } else {
                    try await viewModel.repository.deleteBranch(name: branch.name, force: forceDelete)
                    viewModel.actions.recordBranchDeletion(branch)
                }
                if deleteRemote, let upstreamParts {
                    try await viewModel.repository.deleteRemoteBranch(name: upstreamParts.name, remote: upstreamParts.remote)
                }
                await viewModel.didChangeRepository()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isDeleting = false
                await viewModel.didChangeRepository()
            }
        }
    }
}

#Preview {
    DeleteBranchDialogView(viewModel: SidebarViewModel(repository: MockGitRepository()), branch: MockData.branches[1])
}
