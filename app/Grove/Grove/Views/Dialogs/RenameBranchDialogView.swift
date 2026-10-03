// Views/Dialogs/RenameBranchDialogView.swift
// Grove

import GroveKit
import SwiftUI

/// Renames a local branch.
struct RenameBranchDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let branch: BranchInfo
    var onComplete: () -> Void = {}

    @State private var newName: String
    @State private var isRenaming = false
    @State private var errorMessage: String?

    init(repository: any GitRepositoryProtocol, branch: BranchInfo, onComplete: @escaping () -> Void = {}) {
        self.repository = repository
        self.branch = branch
        self.onComplete = onComplete
        _newName = State(initialValue: branch.name)
    }

    private var trimmedName: String { newName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        DialogSheet(
            title: "Rename \(branch.name)",
            message: "Only the local branch is renamed; its remote counterpart keeps its name.",
            symbol: "pencil",
            width: 420,
            progress: isRenaming ? "Renaming…" : nil,
            errorMessage: errorMessage,
            primaryTitle: "Rename",
            isPrimaryDisabled: trimmedName.isEmpty || trimmedName.contains(" ") || trimmedName == branch.name,
            onCancel: { dismiss() },
            onPrimary: performRename
        ) {
            DialogCard {
                DialogField("New Name") {
                    TextField("Branch name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func performRename() {
        isRenaming = true
        errorMessage = nil
        Task {
            do {
                try await repository.renameBranch(oldName: branch.name, newName: trimmedName)
                onComplete()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isRenaming = false
            }
        }
    }
}

#Preview {
    RenameBranchDialogView(repository: MockGitRepository(), branch: MockData.branches[1])
}
