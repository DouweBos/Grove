// Views/Dialogs/RebaseDialogView.swift
// Grove

import SwiftUI

/// Rebases the checked-out branch onto another branch.
struct RebaseDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let localBranches: [BranchInfo]
    var onComplete: () -> Void = {}

    @State private var selectedBranch: String
    @State private var autoStash = false
    @State private var isRebasing = false
    @State private var errorMessage: String?

    init(
        repository: any GitRepositoryProtocol,
        localBranches: [BranchInfo] = [],
        onComplete: @escaping () -> Void = {}
    ) {
        self.repository = repository
        self.localBranches = localBranches
        self.onComplete = onComplete
        _selectedBranch = State(initialValue: localBranches.first(where: { !$0.isHEAD })?.name ?? "")
    }

    private var candidates: [String] { localBranches.filter { !$0.isHEAD }.map(\.name) }
    private var headName: String { repository.currentBranch?.name ?? "HEAD" }

    var body: some View {
        DialogSheet(
            title: "Rebase \(headName)",
            message: "Replays the commits of '\(headName)' on top of the chosen branch, rewriting their history.",
            symbol: "arrow.triangle.pull",
            progress: isRebasing ? "Rebasing onto \(selectedBranch)…" : nil,
            errorMessage: errorMessage,
            primaryTitle: "Rebase",
            isPrimaryDisabled: selectedBranch.isEmpty,
            onCancel: { dismiss() },
            onPrimary: performRebase
        ) {
            DialogCard {
                DialogField("Onto") {
                    Picker("Onto", selection: $selectedBranch) {
                        ForEach(candidates, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(candidates.isEmpty)
                }
                DialogOptionRow(
                    isOn: $autoStash,
                    label: "Stash Local Changes",
                    description: "Stashes uncommitted changes first and restores them afterwards."
                )
            }
        }
        // Opened before the refs first loaded: pick a branch once they arrive.
        .onChange(of: candidates) { _, names in
            if selectedBranch.isEmpty, let first = names.first { selectedBranch = first }
        }
    }

    private func performRebase() {
        isRebasing = true
        errorMessage = nil
        Task {
            do {
                let didStash = autoStash ? try await stashIfDirty(repository, message: "Grove: auto-stash before rebase") : false
                try await repository.rebase(onto: selectedBranch)
                if didStash {
                    try await repository.stashApply(index: 0, drop: true)
                }
                onComplete()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isRebasing = false
                onComplete()
            }
        }
    }
}

#Preview {
    RebaseDialogView(repository: MockGitRepository(), localBranches: MockData.branches.filter(\.isLocal))
}
