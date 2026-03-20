// Views/Dialogs/RenameBranchDialogView.swift
// Grove

import SwiftUI

/// Dialog for renaming a branch.
struct RenameBranchDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let branch: BranchInfo

    @State private var newName: String
    @State private var isRenaming = false
    @State private var errorMessage: String?

    init(repository: any GitRepositoryProtocol, branch: BranchInfo) {
        self.repository = repository
        self.branch = branch
        _newName = State(initialValue: branch.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Rename Branch",
                description: "Rename '\(branch.name)' to a new name."
            )

            Divider()

            Form {
                LabeledContent("New Name") {
                    TextField("Branch name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                }
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
                primaryLabel: isRenaming ? "Renaming\u{2026}" : "Rename",
                primaryAction: performRename,
                isPrimaryDisabled: isRenaming || newName.isEmpty || newName == branch.name
            )
        }
        .frame(width: 400)
    }

    private func performRename() {
        isRenaming = true
        errorMessage = nil
        Task {
            do {
                try await repository.renameBranch(oldName: branch.name, newName: newName)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isRenaming = false
            }
        }
    }
}
