// Views/Merge/ConflictBannerView.swift
// Grove
//
// Replaces the commit composer while a merge, rebase, cherry-pick or revert is
// in progress: what is happening, how many conflicts remain, and Abort / Resolve / Continue.

import SwiftUI

struct ConflictBannerView: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @State private var isConfirmingAbort = false

    var body: some View {
        let remaining = viewModel.conflictedFiles.count

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Banner(symbol: remaining == 0 ? "checkmark.circle" : "exclamationmark.triangle",
                   message: title)

            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: remaining == 0 ? "checkmark.circle.fill" : "circle.fill")
                    .font(.system(size: remaining == 0 ? 12 : 7))
                    .foregroundStyle(remaining == 0 ? Theme.success : Theme.conflicted)
                Text(remaining == 0 ? "All conflicts resolved" : "\(remaining) \(remaining == 1 ? "conflict" : "conflicts") remaining")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
                if remaining > 0 {
                    Toggle("Only conflicts", isOn: Binding(get: { viewModel.showOnlyConflicts },
                                                            set: { viewModel.setShowOnlyConflicts($0) }))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button("Abort", role: .destructive) { isConfirmingAbort = true }
                Spacer(minLength: 0)
                if viewModel.isRunningOperation {
                    ProgressView().controlSize(.small)
                }
                if remaining > 0 {
                    Button("Resolve…") { Task { await viewModel.resolveNextConflict() } }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Continue \(operationName)") { Task { await viewModel.continueOperation() } }
                        .buttonStyle(.borderedProminent)
                }
            }
            .controlSize(.large)
            .disabled(viewModel.isRunningOperation)
        }
        .card(padding: Theme.Spacing.md)
        .confirmationDialog("Abort the \(operationName.lowercased())?", isPresented: $isConfirmingAbort) {
            Button("Abort \(operationName)", role: .destructive) { Task { await viewModel.abortOperation() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your repository returns to the state before the \(operationName.lowercased()) started. Conflict resolutions are lost.")
        }
    }

    private var operationName: String {
        switch viewModel.repositoryState {
        case .rebase, .rebaseInteractive: "Rebase"
        case .cherrypick: "Cherry-Pick"
        case .revert: "Revert"
        default: "Merge"
        }
    }

    private var title: String {
        let ours = viewModel.operationContext?.oursLabel ?? viewModel.repository.currentBranch?.name ?? "HEAD"
        let theirs = viewModel.operationContext?.theirsLabel ?? "…"
        switch viewModel.repositoryState {
        case .rebase, .rebaseInteractive: return "Rebasing \(theirs) onto \(ours)"
        case .cherrypick: return "Cherry-picking \(theirs) onto \(ours)"
        case .revert: return "Applying \(theirs) on \(ours)"
        default: return "Merging \(theirs) into \(ours)"
        }
    }
}

#Preview("Merge in progress") {
    let repo = MockGitRepository()
    repo.repositoryState = .merge
    let vm = WorkingCopyViewModel(repository: repo)
    return ConflictBannerView()
        .environment(vm)
        .frame(width: 340)
        .padding()
        .background(Theme.background)
        .task { await vm.refresh() }
}
