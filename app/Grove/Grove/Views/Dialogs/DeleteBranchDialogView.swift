// Views/Dialogs/DeleteBranchDialogView.swift
// Grove

import SwiftUI

/// Confirms deleting a local branch, optionally forcing it or removing its remote counterpart.
struct DeleteBranchDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let branch: BranchInfo
    var onComplete: () -> Void = {}

    @State private var forceDelete = false
    @State private var deleteRemote = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    /// "origin" and "feature/x" from an upstream like "origin/feature/x".
    private var upstreamParts: (remote: String, name: String)? {
        guard let upstream = branch.upstreamShortName, let slash = upstream.firstIndex(of: "/") else { return nil }
        return (String(upstream[..<slash]), String(upstream[upstream.index(after: slash)...]))
    }

    var body: some View {
        DialogSheet(
            title: "Delete \(branch.name)?",
            message: "Removes the local branch. Commits that no other branch contains can only be recovered from the reflog.",
            symbol: "trash",
            width: 440,
            progress: isDeleting ? "Deleting \(branch.name)…" : nil,
            errorMessage: errorMessage,
            primaryTitle: "Delete",
            isDestructive: true,
            isPrimaryDisabled: branch.isHEAD,
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
            }
            if branch.isHEAD {
                Banner(symbol: "exclamationmark.triangle", message: "You can't delete the checked-out branch. Check out another branch first.")
            }
        }
    }

    private func performDelete() {
        isDeleting = true
        errorMessage = nil
        Task {
            do {
                try await repository.deleteBranch(name: branch.name, force: forceDelete)
                if deleteRemote, let upstreamParts {
                    try await repository.deleteRemoteBranch(name: upstreamParts.name, remote: upstreamParts.remote)
                }
                onComplete()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isDeleting = false
                onComplete()
            }
        }
    }
}

#Preview {
    DeleteBranchDialogView(repository: MockGitRepository(), branch: MockData.branches[1])
}
