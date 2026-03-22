// Views/Root/RepositoryContentRouter.swift
// Grove
//
// Routes sidebar selection to the appropriate content view inside
// the unified NavigationSplitView detail pane.

import SwiftUI

// MARK: - RepositoryContentRouter

/// Renders the content pane for a loaded repository based on
/// the current sidebar selection.
struct RepositoryContentRouter: View {

    let session: RepositorySession
    let repository: any GitRepositoryProtocol

    // MARK: Body

    var body: some View {
        contentView
            .safeAreaInset(edge: .bottom) {
                StatusBarView(repository: repository, autoFetcher: session.autoFetcher)
            }
            .onChange(of: session.sidebarVM.selection) { _, newItem in
                if let item = newItem {
                    session.selectedItem = item
                }
            }
    }

    // MARK: Content Routing

    @ViewBuilder
    private var contentView: some View {
        switch session.selectedItem {
        case .workingCopy:
            WorkingCopyView(repository: repository)

        case .history:
            HistoryView()
                .environment(session.historyVM)
                .task(id: "history-initial") {
                    await session.historyVM.loadInitial()
                }

        case .stashes:
            StashesView()
                .environment(session.stashesVM)
                .task(id: "stashes-initial") {
                    await session.stashesVM.refresh()
                }

        case .reflog:
            ReflogView()
                .environment(session.reflogVM)
                .task(id: "reflog-initial") {
                    await session.reflogVM.refresh()
                }

        case .blame:
            BlameFilePicker(repository: repository)

        case .pullRequests:
            PullRequestsView()
                .environment(session.pullRequestsVM)
                .task(id: "pullrequests-initial") {
                    await session.pullRequestsVM.refresh()
                }

        case .branchesReview:
            BranchesReviewView()
                .environment(session.branchesReviewVM)
                .task(id: "branchesreview-initial") {
                    await session.branchesReviewVM.refresh()
                }

        case .settings:
            RepositorySettingsView(repository: repository)

        case .branch(let info):
            filteredHistoryView(branch: info.name)

        case .remoteBranch(let info):
            filteredHistoryView(branch: info.name)

        case .tag(let info):
            filteredHistoryView(branch: info.name)
        }
    }

    // MARK: Helpers

    private func filteredHistoryView(branch: String) -> some View {
        let vm = session.filteredHistoryVM(for: branch)
        return HistoryView()
            .environment(vm)
            .task(id: branch) {
                await vm.loadInitial()
            }
    }
}
