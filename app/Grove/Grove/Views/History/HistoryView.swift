// Views/History/HistoryView.swift
// Grove

import SwiftUI

/// The full History view: commit list (left) | commit detail panel (right).
///
/// Uses `HSplitView` to provide a resizable two-column layout.
/// The view model is injected from the parent repository window.
struct HistoryView: View {

    @Environment(HistoryViewModel.self) private var viewModel

    // Sidebar provides branch/tag data for decorating commit rows
    @State private var branches: [BranchInfo] = []
    @State private var tags: [TagInfo] = []

    var body: some View {
        HSplitView {
            // Left: commit list
            CommitListView(branches: branches, tags: tags)
                .frame(minWidth: 280)

            // Right: detail panel
            CommitDetailPanel()
                .frame(minWidth: 300)
                .background(.background)
        }
        .task {
            await loadBranchesAndTags()
        }
        .onChange(of: viewModel.selectedCommit) { _, newCommit in
            if let commit = newCommit {
                Task { await viewModel.selectCommit(commit) }
            }
        }
    }

    private func loadBranchesAndTags() async {
        do {
            async let lb = viewModel.repository.localBranches()
            async let rb = viewModel.repository.remoteBranches()
            async let tg = viewModel.repository.tags()
            let (local, remote, tagList) = try await (lb, rb, tg)
            branches = local + remote
            tags = tagList
        } catch {
            // Non-critical — commit rows just won't have labels
        }
    }
}

#Preview {
    let vm = HistoryViewModel(repository: MockGitRepository())
    return HistoryView()
        .environment(vm)
        .frame(width: 800, height: 500)
}
