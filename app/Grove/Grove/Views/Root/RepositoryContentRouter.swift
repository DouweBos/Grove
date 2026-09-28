// Views/Root/RepositoryContentRouter.swift
// Grove
//
// Routes sidebar selection to the appropriate content view inside
// the unified NavigationSplitView detail pane.

import AppKit
import SwiftUI

// MARK: - RepositoryContentRouter

/// Renders the content pane for a loaded repository based on
/// the current sidebar selection.
struct RepositoryContentRouter: View {

    let session: RepositorySession
    @Environment(WindowViewModel.self) private var windowVM
    let repository: any GitRepositoryProtocol

    // MARK: Body

    var body: some View {
        contentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                StatusBarView(repository: repository, autoFetcher: session.autoFetcher)
            }
            .background(Theme.background)
            .foregroundStyle(Theme.textPrimary)
            // `-GroveAction <rawValue>` runs an action once the repository opens.
            .task {
                if let raw = UserDefaults.standard.string(forKey: "GroveAction"),
                   let action = GroveAction(rawValue: raw) {
                    session.handleAction(action)
                }
            }
            .onChange(of: session.sidebarVM.selection) { _, newItem in
                // Back/forward restores both at once, so only user-driven changes differ here.
                if let item = newItem, item != session.selectedItem {
                    windowVM.recordNavigation(to: .repository(path: session.repository.path.path, item: item))
                    session.selectedItem = item
                }
            }
    }

    // MARK: Content Routing

    @ViewBuilder
    private var contentView: some View {
        switch session.selectedItem {
        case .workingCopy:
            WorkingCopyView(viewModel: session.workingCopyVM)
                .dropDestination(for: String.self) { items, _ in
                    guard let payload = items.first else { return false }
                    return session.sidebarVM.handleWorkingCopyDrop(
                        payload, rebase: NSEvent.modifierFlags.contains(.option)
                    )
                }

        case .history:
            HistoryView()
                .environment(session.historyVM)

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
            BlameView(viewModel: session.blameVM)

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
            RepositorySettingsView(viewModel: session.repositorySettingsVM)

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
                await vm.loadIfNeeded()
            }
    }
}
