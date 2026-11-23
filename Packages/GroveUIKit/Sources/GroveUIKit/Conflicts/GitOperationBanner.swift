// Conflicts/GitOperationBanner.swift
// GroveUIKit
//
// In the composer's place while a merge, rebase, cherry-pick or revert runs: what is happening,
// how many conflicts are left, and Abort, Resolve or Continue.

#if os(macOS)
import GroveKit
import SwiftUI

struct GitOperationBanner: View {
    @Environment(\.gitStyle) private var style
    @Environment(WorkingCopyViewModel.self) private var viewModel
    /// Off where the conflicts are listed beside it anyway.
    var showsOnlyConflicts = true
    @State private var isConfirmingAbort = false

    var body: some View {
        let remaining = viewModel.conflictedFiles.count

        VStack(alignment: .leading, spacing: GitMetrics.Spacing.md) {
            GitBanner(symbol: remaining == 0 ? "checkmark.circle" : "exclamationmark.triangle", message: title)

            HStack(spacing: GitMetrics.Spacing.sm) {
                Image(systemName: remaining == 0 ? "checkmark.circle.fill" : "circle.fill")
                    .font(style.font(remaining == 0 ? 12 : 7))
                    .foregroundStyle(remaining == 0 ? style.success : style.warning)
                Text(remaining == 0 ? "All conflicts resolved" : "\(remaining) \(remaining == 1 ? "conflict" : "conflicts") remaining")
                    .font(style.font(12, .medium))
                    .foregroundStyle(style.textPrimary)
                Spacer(minLength: 0)
                if remaining > 0, showsOnlyConflicts {
                    Toggle("Only conflicts", isOn: Binding(get: { viewModel.showOnlyConflicts },
                                                            set: { viewModel.setShowOnlyConflicts($0) }))
                        .toggleStyle(.checkbox)
                        .gitClickable()
                        .font(style.font(12))
                        .foregroundStyle(style.textSecondary)
                }
            }

            HStack(spacing: GitMetrics.Spacing.sm) {
                Button("Abort", role: .destructive) { isConfirmingAbort = true }
                    .gitClickable()
                Spacer(minLength: 0)
                if viewModel.isRunningOperation {
                    ProgressView().controlSize(.small)
                }
                if remaining > 0 {
                    Button("Resolve") { Task { await viewModel.resolveNextConflict() } }
                        .buttonStyle(.borderedProminent)
                        .gitClickable()
                        .help("Show the next conflicted file")
                } else {
                    Button(viewModel.pendingRestack == nil ? "Continue \(operationName)" : "Continue Restack") {
                        viewModel.act { await viewModel.continueOperation() }
                    }
                    .buttonStyle(.borderedProminent)
                    .gitClickable()
                }
            }
            .controlSize(.large)
            .disabled(viewModel.isRunningOperation)
        }
        .gitCard(padding: GitMetrics.Spacing.md)
        .confirmationDialog("Abort the \(operationName.lowercased())?", isPresented: $isConfirmingAbort, titleVisibility: .visible) {
            Button("Abort \(operationName)", role: .destructive) { viewModel.act { await viewModel.abortOperation() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(viewModel.pendingRestack == nil
                 ? "Your repository returns to the state before the \(operationName.lowercased()) started. Conflict resolutions are lost."
                 : "Every branch the restack already moved goes back to where it was. Conflict resolutions are lost.")
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
        if let restack = viewModel.pendingRestack { return restack.progressTitle }
        let ours = viewModel.operationContext?.oursLabel ?? viewModel.repository.currentBranch?.name ?? "HEAD"
        let theirs = viewModel.operationContext?.theirsLabel ?? "another branch"
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
    return GitOperationBanner()
        .environment(vm)
        .frame(width: 340)
        .padding()
        .task { await vm.refresh() }
}
#endif
