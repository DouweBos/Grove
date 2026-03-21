// Views/WorkingCopy/WorkingCopyLeftColumn.swift
// Grove
//
// The left column of the Working Copy layout — a VSplitView with
// CommitComposerView (or ConflictBannerView during conflict states)
// on top and FileStatusListView below.

import SwiftUI

// MARK: - WorkingCopyLeftColumn

/// Left pane of ``WorkingCopyView``: commit composer (top) + file list (bottom).
///
/// When the repository is in a conflict state (`.merge`, `.rebase`,
/// `.cherrypick`, or `.revert`) the commit composer is replaced with
/// ``ConflictBannerView``.
///
/// Consumes ``WorkingCopyViewModel`` from the environment.
struct WorkingCopyLeftColumn: View {

    // MARK: Environment

    @Environment(WorkingCopyViewModel.self) private var viewModel

    // MARK: Body

    var body: some View {
        VSplitView {
            composerOrConflictBanner
                .frame(minHeight: 120, idealHeight: 170, maxHeight: 260)

            FileStatusListView()
                .frame(minHeight: 100, maxHeight: .infinity)
        }
    }

    // MARK: Composer vs Conflict Banner

    /// Returns the commit composer for `.normal` state, or `ConflictBannerView`
    /// for any active merge/rebase/cherry-pick/revert conflict state.
    @ViewBuilder
    private var composerOrConflictBanner: some View {
        let state = viewModel.repository.repositoryState
        if isConflictState(state) {
            conflictBanner(for: state)
        } else {
            CommitComposerView()
        }
    }

    // MARK: Conflict Banner Builder

    private func conflictBanner(for state: RepositoryState) -> some View {
        let branch = viewModel.repository.currentBranch?.name ?? "HEAD"
        let conflicts = viewModel.statusEntries.filter {
            $0.indexStatus == .conflicted || $0.workdirStatus == .conflicted
        }

        return ConflictBannerView(
            repository: viewModel.repository,
            repositoryState: state,
            sourceBranch: branch,
            targetBranch: branch,
            totalConflicts: max(conflicts.count, 1),
            remainingConflicts: conflicts.count,
            showOnlyConflicts: conflictsBinding
        )
    }

    // MARK: Helpers

    private func isConflictState(_ state: RepositoryState) -> Bool {
        switch state {
        case .merge, .rebase, .rebaseInteractive, .cherrypick, .revert:
            return true
        default:
            return false
        }
    }

    private var conflictsBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showOnlyConflicts },
            set: { viewModel.showOnlyConflicts = $0 }
        )
    }
}

// MARK: - Preview

#Preview("Left Column — Normal") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    WorkingCopyLeftColumn()
        .environment(vm)
        .frame(width: 280, height: 600)
        .task { await vm.refresh() }
}

#Preview("Left Column — Merge Conflict") {
    let repo = MockGitRepository()
    repo.repositoryState = .merge
    let vm = WorkingCopyViewModel(repository: repo)
    return WorkingCopyLeftColumn()
        .environment(vm)
        .frame(width: 280, height: 600)
        .task { await vm.refresh() }
}
