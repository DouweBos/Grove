// Views/History/CommitDetailPanel.swift
// Grove

import SwiftUI

/// Right panel of History: commit header, then its changeset or tree.
struct CommitDetailPanel: View {
    @Environment(HistoryViewModel.self) private var viewModel

    var body: some View {
        Group {
            if viewModel.selection.count > 1 {
                CommitSelectionSummary(commits: viewModel.selectedCommits)
            } else if let commit = viewModel.selectedCommit {
                VStack(spacing: 0) {
                    PanelHeader(title: commit.shortSHA) {
                        Picker("View", selection: Binding(get: { viewModel.detailTab }, set: { viewModel.selectDetailTab($0) })) {
                            ForEach(HistoryViewModel.DetailTab.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            CommitDetailHeader(commit: commit)
                                .padding(Theme.Spacing.lg)
                            Rectangle().fill(Theme.border).frame(height: 0.5)
                            switch viewModel.detailTab {
                            case .changeset: CommitChangesetView()
                            case .tree: CommitTreeTab()
                            }
                        }
                    }
                    .id(commit.id)
                }
            } else {
                EmptyStateView(systemImage: "clock.arrow.circlepath", title: "No Commit Selected",
                               subtitle: "Pick a commit on the left to see its changes.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panel()
    }
}

#Preview {
    let vm = HistoryViewModel(repository: MockGitRepository())
    return CommitDetailPanel()
        .environment(vm)
        .frame(width: 560, height: 640)
        .padding()
        .background(Theme.background)
        .task { await vm.loadInitial() }
}
