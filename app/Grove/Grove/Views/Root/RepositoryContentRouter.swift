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
            .sheet(item: Binding(get: { session.pullRequestsVM.creation },
                                 set: { if $0 == nil { session.pullRequestsVM.cancelCreatePullRequest() } })) { creation in
                CreatePullRequestSheet(viewModel: creation) { session.pullRequestsVM.cancelCreatePullRequest() }
            }
            .sheet(item: Binding(get: { session.ciVM.dispatch }, set: { if $0 == nil { session.ciVM.cancelDispatch() } })) { dispatch in
                DispatchWorkflowSheet(viewModel: dispatch) { session.ciVM.cancelDispatch() }
            }
            // Stacks load after the tab opens, and a stack can vanish under it, so selection follows the shown stack.
            .onChange(of: session.stackVM.stack?.id) { _, id in
                guard let id, RepositoryTab(item: session.sidebarVM.selection ?? .workingCopy) == .stack else { return }
                session.sidebarVM.select(.branchStack(id))
            }
            .onChange(of: session.sidebarVM.selection) { _, newItem in
                // Back/forward restores both at once, so only user-driven changes differ here.
                // The Stack tab always selects the stack it shows, so that stack's sidebar folder stays lit.
                if newItem == .stack, let id = session.stackVM.stack?.id {
                    session.sidebarVM.select(.branchStack(id))
                    return
                }
                if case .branch(let branch) = newItem { session.stackVM.focus(branch: branch.name) }
                if case .branchStack(let id) = newItem { session.stackVM.focus(branch: id) }
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
                    await session.refreshOnEntry(.stashes)
                }

        case .reflog:
            ReflogView()
                .environment(session.reflogVM)
                .task(id: "reflog-initial") {
                    await session.refreshOnEntry(.reflog)
                }

        case .blame:
            BlameView(viewModel: session.blameVM)

        case .pullRequests:
            PullRequestsView()
                .environment(session.pullRequestsVM)
                .task(id: "pullrequests-initial") {
                    await session.refreshOnEntry(.pullRequests)
                }

        case .ci:
            CIView()
                .environment(session.ciVM)
                .task(id: "ci-initial") {
                    await session.refreshOnEntry(.ci)
                    await session.ciVM.pollWhileVisible()
                }

        case .branchesReview:
            BranchesReviewView()
                .environment(session.branchesReviewVM)
                .task(id: "branchesreview-initial") {
                    await session.refreshOnEntry(.branchesReview)
                }

        case .stack, .branchStack:
            StackView()
                .environment(session.stackVM)
                .task(id: "stack-initial") {
                    await session.refreshOnEntry(.stack)
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
