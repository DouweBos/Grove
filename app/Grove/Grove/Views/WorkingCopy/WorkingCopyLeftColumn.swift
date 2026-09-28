// Views/WorkingCopy/WorkingCopyLeftColumn.swift
// Grove
//
// Left column of the Changes tab: commit composer (or the conflict banner while
// a merge/rebase is in progress) above the file list.

import SwiftUI

struct WorkingCopyLeftColumn: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    /// Horizontal when the Changes tab stacks the diff underneath in narrow windows.
    var axis: Axis = .vertical

    var body: some View {
        if axis == .vertical {
            VStack(spacing: Theme.Spacing.md) {
                composer
                FileStatusListView()
            }
        } else {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                composer.frame(maxWidth: .infinity)
                FileStatusListView().frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var composer: some View {
        if viewModel.lfs.status.isMissing {
            Banner(symbol: "externaldrive.badge.exclamationmark", message: LFSStatus.missingMessage)
        }
        if viewModel.isInOperation {
            ConflictBannerView()
        } else {
            CommitComposerView()
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
