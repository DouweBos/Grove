// Dialogs/Views/DeleteBranchDialog.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// Confirms deleting a local branch, optionally forcing it, removing its remote counterpart,
/// or first removing the worktree that has it checked out.
struct DeleteBranchDialog: View {
    let context: GitDialogContext
    let close: (Bool) -> Void
    @State private var form: GitDeleteBranchForm
    /// Commits only this branch has, read when the dialog opens.
    @State private var unmerged = 0
    @State private var operation = DialogOperation()

    init(branch: BranchInfo, context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        _form = State(initialValue: GitDeleteBranchForm(branch: branch))
    }

    private var branch: BranchInfo { form.branch }
    private var features: GitFeatures { context.features }
    /// Read live, so it clears once the worktree is gone even if deleting the branch then fails.
    private var worktree: WorktreeInfo? { context.worktrees?.checkingOut(branch) }
    private var isBlocked: Bool { branch.isHEAD || (worktree != nil && !form.removeWorktree) }
    private var head: String { context.headBranch?.name ?? "HEAD" }

    var body: some View {
        GitDialogSheet(
            title: "Delete \(branch.name)?",
            message: "Removes the local branch. Commits that no other branch contains can only be recovered from the reflog.",
            symbol: "trash", width: 440,
            progress: operation.title, errorMessage: operation.errorMessage,
            primaryTitle: worktree != nil && form.removeWorktree ? "Remove Worktree and Delete" : "Delete",
            isDestructive: true, isPrimaryDisabled: isBlocked, blocker: form.unsupportedReason(features),
            onCancel: { close(false) },
            onPrimary: { operation.submit("Deleting \(branch.name)", form, context: context, close: close) }
        ) {
            GitDialogCard {
                GitDialogOptionRow(isOn: $form.force, label: "Delete Even if Unmerged",
                                   description: "Required when the branch has commits that aren't merged anywhere.")
                if let upstream = form.upstream, features.contains(.push) {
                    GitDialogOptionRow(isOn: $form.deleteRemote, label: "Also Delete \(upstream.remote)/\(upstream.name)",
                                       description: "Removes the branch on the remote for everyone.")
                }
                if let worktree {
                    GitDialogOptionRow(isOn: $form.removeWorktree, label: "Remove Its Worktree First",
                                       description: "Deletes the folder \(abbreviatingHome(worktree.path)).")
                    if form.removeWorktree {
                        GitDialogOptionRow(isOn: $form.discardWorktreeChanges, label: "Remove Even with Uncommitted Changes",
                                           description: "Discards the worktree's modified and untracked files.")
                    }
                }
            }
            banner
        }
        .task {
            // Branches HEAD lacks commits of need -D; say so up front rather than after git refuses.
            let counts = try? await context.repository.aheadBehind(branch: branch.name, base: "HEAD")
            unmerged = counts?.ahead ?? 0
            if unmerged > 0 { form.force = true }
        }
    }

    @ViewBuilder
    private var banner: some View {
        if branch.isHEAD {
            GitBanner(symbol: "exclamationmark.triangle", message: "You can't delete the checked-out branch. Check out another branch first.")
        } else if let worktree {
            GitBanner(symbol: "tree",
                      message: "Checked out in the worktree at \(abbreviatingHome(worktree.path)). Git can't delete it while it's checked out there.",
                      actionTitle: "Open Worktree",
                      action: {
                          context.worktrees?.open(worktree)
                          close(false)
                      })
        } else if unmerged > 0 {
            GitBanner(symbol: "exclamationmark.triangle",
                      message: "\(branch.name) has \(unmerged) commit\(unmerged == 1 ? "" : "s") \(head) doesn't. Deleting it loses them.")
        }
    }
}

/// `~/Projects/x` instead of `/Users/me/Projects/x`.
func abbreviatingHome(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

/// Sets the remote branch a local branch pulls from and compares against.
struct TrackDialog: View {
    @Environment(\.gitStyle) private var style
    let context: GitDialogContext
    let close: (Bool) -> Void
    @State private var form: GitTrackForm
    @State private var operation = DialogOperation()

    init(branch: BranchInfo, context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        _form = State(initialValue: GitTrackForm(branch: branch, remoteBranches: Self.candidates(context.refs),
                                                 remotes: context.refs.remotes))
    }

    static func candidates(_ refs: RepositoryRefs) -> [String] {
        refs.remoteBranches.map(\.name).filter { !$0.hasSuffix("/HEAD") }
    }

    var body: some View {
        GitDialogSheet(
            title: "Track Remote Branch",
            message: "\u{201C}\(form.branch.name)\u{201D} pulls from this branch, which also tells how far ahead or behind of it you are.",
            symbol: "arrow.left.arrow.right",
            progress: operation.title, errorMessage: operation.errorMessage,
            primaryTitle: "Track", isPrimaryDisabled: form.commands.isEmpty, blocker: form.unsupportedReason(context.features),
            onCancel: { close(false) },
            onPrimary: { operation.submit("Tracking \(form.upstream.trimmed)", form, context: context, close: close) }
        ) {
            GitDialogCard {
                GitDialogField("Remote Branch") {
                    GitComboBox(text: $form.upstream, items: Self.candidates(context.refs), placeholder: "remote/branch",
                                isMonospaced: true)
                        .gitInitialFocus()
                }
            }
            if Self.candidates(context.refs).isEmpty {
                GitBanner(symbol: "exclamationmark.triangle", message: "There are no remote branches yet. Add a remote or fetch first.")
            }
        }
    }
}
#endif
