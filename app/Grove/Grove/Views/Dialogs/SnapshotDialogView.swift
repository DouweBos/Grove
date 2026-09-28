// Views/Dialogs/SnapshotDialogView.swift
// Grove

import SwiftUI

/// Saves the working state as a stash while leaving every change in place.
struct SnapshotDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    var onComplete: () -> Void = {}

    @State private var message: String
    @State private var includeUntracked = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(repository: any GitRepositoryProtocol, onComplete: @escaping () -> Void = {}) {
        self.repository = repository
        self.onComplete = onComplete
        _message = State(initialValue: Self.defaultMessage(branch: repository.currentBranch?.name))
    }

    static func defaultMessage(branch: String?, date: Date = .now) -> String {
        "Snapshot of \(branch ?? "HEAD"), \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        DialogSheet(
            title: "Save Snapshot",
            message: "Keeps a copy of your uncommitted changes in the stash list. Your working copy isn't touched.",
            symbol: "camera.aperture",
            progress: isSaving ? "Saving\u{2026}" : nil,
            errorMessage: errorMessage,
            primaryTitle: "Save Snapshot",
            isPrimaryDisabled: trimmed.isEmpty,
            onCancel: { dismiss() },
            onPrimary: save
        ) {
            DialogCard {
                DialogField("Message") {
                    TextField("Snapshot message", text: $message)
                        .textFieldStyle(.roundedBorder)
                }
                DialogOptionRow(isOn: $includeUntracked, label: "Include Untracked Files")
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let saved = try await repository.saveSnapshot(message: trimmed, includeUntracked: includeUntracked)
                guard saved else {
                    errorMessage = "There are no local changes to snapshot."
                    isSaving = false
                    return
                }
                onComplete()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
            }
        }
    }
}

#Preview {
    SnapshotDialogView(repository: MockGitRepository())
}
