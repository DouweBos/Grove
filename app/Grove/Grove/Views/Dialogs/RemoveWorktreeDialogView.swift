// Views/Dialogs/RemoveWorktreeDialogView.swift
// Grove

import SwiftUI

/// Confirms removing a linked worktree, optionally with its uncommitted changes and its branch.
struct RemoveWorktreeDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let viewModel: SidebarViewModel
    let worktree: WorktreeInfo

    @State private var force = false
    @State private var deleteBranch = false
    @State private var forceDeleteBranch = false
    @State private var isRemoving = false
    @State private var errorMessage: String?

    private var branch: BranchInfo? { viewModel.branch(checkedOutIn: worktree) }
    private var title: String { worktree.branch ?? worktree.folderName }

    var body: some View {
        DialogSheet(
            title: "Remove the worktree \u{201C}\(title)\u{201D}?",
            message: "Deletes the folder \(abbreviatingHome(worktree.path)). Commits stay in the repository.",
            symbol: "trash",
            width: 440,
            progress: isRemoving ? "Removing \(title)…" : nil,
            errorMessage: errorMessage,
            primaryTitle: deleteBranch ? "Remove and Delete Branch" : "Remove",
            isDestructive: true,
            onCancel: { dismiss() },
            onPrimary: performRemove
        ) {
            DialogCard {
                DialogOptionRow(
                    isOn: $force,
                    label: "Remove Even with Uncommitted Changes",
                    description: "Discards the worktree's modified and untracked files."
                )
                if let branch {
                    DialogOptionRow(
                        isOn: $deleteBranch,
                        label: "Also Delete Branch \(branch.name)",
                        description: "Otherwise the branch is kept and can be checked out elsewhere."
                    )
                    if deleteBranch {
                        DialogOptionRow(
                            isOn: $forceDeleteBranch,
                            label: "Delete Even if Unmerged",
                            description: "Required when the branch has commits that aren't merged anywhere."
                        )
                    }
                }
            }
        }
    }

    private func performRemove() {
        isRemoving = true
        errorMessage = nil
        Task {
            do {
                try await viewModel.removeWorktree(worktree, force: force,
                                                   deleting: deleteBranch ? branch : nil, forceBranch: forceDeleteBranch)
                await viewModel.didChangeRepository()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isRemoving = false
                await viewModel.didChangeRepository()
            }
        }
    }
}

#Preview {
    RemoveWorktreeDialogView(
        viewModel: SidebarViewModel(repository: MockGitRepository()),
        worktree: WorktreeInfo(path: "/Users/dev/Projects/my-app-feature-auth", branch: "feature/auth",
                               headSHA: "a1b2c3d", isMain: false, isPrunable: false, isLocked: false)
    )
}
