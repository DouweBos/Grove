// Views/Dialogs/StashDialogView.swift
// Grove
//
// Stash creation dialog: message field, include-untracked toggle.

import SwiftUI

// MARK: - StashDialogView

/// Dialog for creating a new stash.
struct StashDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol

    @State private var message = ""
    @State private var includeUntracked = true
    @State private var isStashing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Stash Changes",
                description: "Saves your local modifications to a new stash entry and reverts the working directory to match HEAD."
            )

            Divider()

            Form {
                LabeledContent("Message") {
                    TextField("Optional stash message", text: $message)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Include Untracked Files", isOn: $includeUntracked)
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
                primaryLabel: isStashing ? "Stashing\u{2026}" : "Stash",
                primaryAction: performStash,
                isPrimaryDisabled: isStashing
            )
        }
        .frame(width: 440)
    }

    private func performStash() {
        isStashing = true
        errorMessage = nil
        Task {
            do {
                let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
                try await repository.stashCreate(
                    message: msg.isEmpty ? nil : msg,
                    includeUntracked: includeUntracked
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isStashing = false
            }
        }
    }
}

#Preview {
    StashDialogView(repository: MockGitRepository())
}
