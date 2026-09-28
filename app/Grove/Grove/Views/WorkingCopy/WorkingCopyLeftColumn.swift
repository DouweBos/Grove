// Views/WorkingCopy/WorkingCopyLeftColumn.swift
// Grove
//
// Left column of the Changes tab: commit composer (or the conflict banner while
// a merge/rebase is in progress) above the file list.

import SwiftUI

struct WorkingCopyLeftColumn: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            if viewModel.isInOperation {
                ConflictBannerView()
            } else {
                CommitComposerView()
            }
            FileStatusListView()
        }
    }
}

#Preview("Left Column") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    WorkingCopyLeftColumn()
        .environment(vm)
        .frame(width: 340, height: 700)
        .padding()
        .background(Theme.background)
        .task { await vm.refresh() }
}
