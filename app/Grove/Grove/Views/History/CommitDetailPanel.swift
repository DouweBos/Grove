// Views/History/CommitDetailPanel.swift
// Grove

import SwiftUI

/// Right panel of the History view showing commit details.
///
/// Contains a header (author, SHA, message) and tabbed content: Changeset | Tree.
struct CommitDetailPanel: View {

    @Environment(HistoryViewModel.self) private var viewModel
    @State private var selectedTab: DetailTab = .changeset

    enum DetailTab: String, CaseIterable {
        case changeset = "Changeset"
        case tree = "Tree"
    }

    var body: some View {
        if let commit = viewModel.selectedCommit {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                CommitDetailHeader(commit: commit)
                    .padding(12)

                Divider()

                // Tab selector
                Picker("Tab", selection: $selectedTab) {
                    ForEach(DetailTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                // Tab content
                switch selectedTab {
                case .changeset:
                    CommitChangesetView()
                case .tree:
                    CommitTreeTab()
                }
            }
        } else {
            // Empty state
            VStack(spacing: 8) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 40))
                    .foregroundStyle(.tertiary)
                Text("Select a commit to view details")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    let vm = HistoryViewModel(repository: MockGitRepository())
    vm.selectedCommit = MockData.commits[0]
    vm.commitDiffs = MockData.commitFileDiffs

    return CommitDetailPanel()
        .environment(vm)
        .frame(width: 420, height: 600)
}
