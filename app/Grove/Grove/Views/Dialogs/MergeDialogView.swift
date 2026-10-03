// Views/Dialogs/MergeDialogView.swift
// Grove

import GroveKit
import SwiftUI

/// Merges a chosen branch into the checked-out branch.
struct MergeDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let localBranches: [BranchInfo]
    var onComplete: () -> Void = {}

    @State private var selectedBranch: String
    @State private var isMerging = false
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
            title: "Merge into \(headName)",
            message: "Brings the commits of the chosen branch into '\(headName)'. Conflicts are left for you to resolve.",
            symbol: "arrow.triangle.merge",
            progress: isMerging ? "Merging \(selectedBranch)…" : nil,
            errorMessage: errorMessage,
            primaryTitle: "Merge",
            isPrimaryDisabled: selectedBranch.isEmpty,
            onCancel: { dismiss() },
            onPrimary: performMerge
        ) {
            DialogCard {
                DialogField("Branch") {
                    Picker("Branch", selection: $selectedBranch) {
                        ForEach(candidates, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(candidates.isEmpty)
                }
            }
        }
        // Opened before the refs first loaded: pick a branch once they arrive.
        .onChange(of: candidates) { _, names in
            if selectedBranch.isEmpty, let first = names.first { selectedBranch = first }
        }
    }

    private func performMerge() {
        isMerging = true
        errorMessage = nil
        Task {
            do {
                try await repository.merge(branch: selectedBranch)
                onComplete()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isMerging = false
                // A conflicted merge still changed the working copy.
                onComplete()
            }
        }
    }
}

#Preview {
    MergeDialogView(repository: MockGitRepository(), localBranches: MockData.branches.filter(\.isLocal))
}
