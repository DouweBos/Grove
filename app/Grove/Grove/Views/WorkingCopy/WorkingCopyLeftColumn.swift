// Views/WorkingCopy/WorkingCopyLeftColumn.swift
// Grove
//
// The left column of the Working Copy layout — a VSplitView with
// CommitComposerView on top and FileStatusListView below.

import SwiftUI

// MARK: - WorkingCopyLeftColumn

/// Left pane of ``WorkingCopyView``: commit composer (top) + file list (bottom).
///
/// Consumes ``WorkingCopyViewModel`` from the environment.
struct WorkingCopyLeftColumn: View {

    // MARK: Environment

    @Environment(WorkingCopyViewModel.self) private var viewModel

    // MARK: Body

    var body: some View {
        VSplitView {
            CommitComposerView()
                .frame(minHeight: 120, idealHeight: 170, maxHeight: 260)

            FileStatusListView()
                .frame(minHeight: 100, maxHeight: .infinity)
        }
    }
}

// MARK: - Preview

#Preview("Left Column") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    WorkingCopyLeftColumn()
        .environment(vm)
        .frame(width: 280, height: 600)
        .task { await vm.refresh() }
}
