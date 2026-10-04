// Views/Dialogs/RenameBranchDialogView.swift
// Grove

import GroveKit
import SwiftUI

/// Renames a local branch.
struct RenameBranchDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let branch: BranchInfo
    /// Renames the branch, throwing for the dialog to show.
    let rename: (String) async throws -> Void

    @State private var newName: String
    @State private var isRenaming = false
    @State private var errorMessage: String?

    init(branch: BranchInfo, rename: @escaping (String) async throws -> Void) {
        self.branch = branch
        self.rename = rename
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
                try await rename(trimmedName)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isRenaming = false
            }
        }
    }
}

#Preview {
    RenameBranchDialogView(branch: MockData.branches[1]) { _ in }
}
