// Views/Dialogs/RebaseDialogView.swift
// Grove
//
// Rebase dialog: target branch picker, Cancel + "Rebase" button.

import SwiftUI

// MARK: - RebaseDialogView

/// Dialog for rebasing the current branch onto another branch.
struct RebaseDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let localBranches: [BranchInfo]

    @State private var selectedBranch: String
    @State private var autoStash = false
    @State private var isRebasing = false
    @State private var errorMessage: String?

    init(
        repository: any GitRepositoryProtocol,
        localBranches: [BranchInfo] = []
    ) {
        self.repository = repository
        self.localBranches = localBranches
        let nonHead = localBranches.first(where: { !$0.isHEAD })
        _selectedBranch = State(initialValue: nonHead?.name ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Rebase",
                description: "Rebases your current HEAD branch '\(repository.currentBranch?.name ?? "HEAD")' onto the selected branch."
            )

            Divider()

            Form {
                LabeledContent("Onto") {
                    Picker("", selection: $selectedBranch) {
                        ForEach(rebaseCandidates, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Auto Stash", isOn: $autoStash)
                        .fontWeight(.medium)
                    Text("Stashes local changes before rebasing and restores them afterwards.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
                .padding(.vertical, 4)
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
                primaryLabel: isRebasing ? "Rebasing\u{2026}" : "Rebase",
                primaryAction: performRebase,
                isPrimaryDisabled: isRebasing || selectedBranch.isEmpty
            )
        }
        .frame(width: 440)
    }

    private var rebaseCandidates: [String] {
        localBranches.filter { !$0.isHEAD }.map(\.name)
    }

    private func performRebase() {
        isRebasing = true
        errorMessage = nil
        Task {
            do {
                // Auto stash: save local changes before rebasing.
                if autoStash {
                    try await repository.stashCreate(
                        message: "auto-stash before rebase",
                        includeUntracked: true,
                        paths: nil
                    )
                }
                try await repository.rebase(onto: selectedBranch)
                // Auto stash: restore local changes after rebasing.
                if autoStash {
                    try await repository.stashApply(index: 0, drop: true)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isRebasing = false
            }
        }
    }
}

#Preview {
    RebaseDialogView(
        repository: MockGitRepository(),
        localBranches: MockData.branches.filter(\.isLocal)
    )
}
