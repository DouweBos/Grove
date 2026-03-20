// Views/Dialogs/DeleteBranchDialogView.swift
// Grove

import SwiftUI

/// Confirmation dialog for deleting a branch.
struct DeleteBranchDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let branch: BranchInfo

    @State private var forceDelete = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Delete Branch",
                description: "Delete the branch '\(branch.name)'. This action cannot be undone."
            )

            Divider()

            Form {
                DialogOptionRow(
                    isOn: $forceDelete,
                    label: "Force Delete",
                    description: "Delete even if the branch has unmerged changes."
                )
            }
            .formStyle(.grouped)

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }

            Divider()

            SheetFooter(
                cancelAction: { dismiss() },
                primaryLabel: isDeleting ? "Deleting\u{2026}" : "Delete",
                primaryAction: performDelete,
                isPrimaryDisabled: isDeleting
            )
        }
        .frame(width: 400)
    }

    private func performDelete() {
        isDeleting = true
        errorMessage = nil
        Task {
            do {
                try await repository.deleteBranch(name: branch.name, force: forceDelete)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isDeleting = false
            }
        }
    }
}
