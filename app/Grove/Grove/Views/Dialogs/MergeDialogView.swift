// Views/Dialogs/MergeDialogView.swift
// Grove
//
// Merge dialog: branch picker, Cancel + "Merge" button.

import SwiftUI

// MARK: - MergeDialogView

/// Dialog for merging a branch into the current HEAD.
struct MergeDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    let localBranches: [BranchInfo]

    @State private var selectedBranch: String
    @State private var isMerging = false
    @State private var errorMessage: String?

    init(
        repository: any GitRepositoryProtocol,
        localBranches: [BranchInfo] = []
    ) {
        self.repository = repository
        self.localBranches = localBranches
        // Default to the first non-HEAD branch.
        let nonHead = localBranches.first(where: { !$0.isHEAD })
        _selectedBranch = State(initialValue: nonHead?.name ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Merge",
                description: "Merges the selected branch into your current HEAD branch '\(repository.currentBranch?.name ?? "HEAD")'."
            )

            Divider()

            Form {
                LabeledContent("Branch") {
                    Picker("", selection: $selectedBranch) {
                        ForEach(mergeCandidates, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                primaryLabel: isMerging ? "Merging\u{2026}" : "Merge",
                primaryAction: performMerge,
                isPrimaryDisabled: isMerging || selectedBranch.isEmpty
            )
        }
        .frame(width: 440)
    }

    private var mergeCandidates: [String] {
        localBranches.filter { !$0.isHEAD }.map(\.name)
    }

    private func performMerge() {
        isMerging = true
        errorMessage = nil
        Task {
            do {
                try await repository.merge(branch: selectedBranch)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isMerging = false
            }
        }
    }
}

#Preview {
    MergeDialogView(
        repository: MockGitRepository(),
        localBranches: MockData.branches.filter(\.isLocal)
    )
}
