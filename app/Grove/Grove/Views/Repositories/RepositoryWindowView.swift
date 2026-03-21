// Views/Repositories/RepositoryWindowView.swift
// Grove
//
// Shell for a per-repository window.
// Hosts a NavigationSplitView whose sidebar is the full RepositorySidebar
// (WS4) and whose detail area routes via RepositoryContentRouter to the
// real view implementations built by WS3/WS4.

import SwiftUI
import os

// MARK: - RepositoryWindowView

/// The top-level view for a repository window.
///
/// Accepts a ``RepositoryReference`` and opens a real ``GitRepository``
/// backed by the git CLI. Falls back to an error state if the path is
/// not a valid git repository. Previews continue to use ``MockGitRepository``.
struct RepositoryWindowView: View {

    // MARK: Input

    let reference: RepositoryReference

    // MARK: State

    /// The resolved repository, loaded asynchronously on first appearance.
    @State private var repository: (any GitRepositoryProtocol)?
    /// Non-nil when the repository could not be opened.
    @State private var openError: String?

    // MARK: Body

    var body: some View {
        Group {
            if let repo = repository {
                RepositoryWindowContent(reference: reference, repository: repo)
            } else if let error = openError {
                errorView(message: error)
            } else {
                loadingView
            }
        }
        .task {
            guard repository == nil, openError == nil else { return }
            let url = URL(fileURLWithPath: reference.path)
            Logger.ui.info("Opening repository window for \(reference.path, privacy: .public)")
            do {
                repository = try await GitRepository(path: url)
                Logger.ui.info("Repository window ready: \(reference.displayName, privacy: .public)")
            } catch {
                Logger.ui.error("Failed to open repository window for \(reference.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                openError = error.localizedDescription
            }
        }
    }

    // MARK: Loading View

    private var loadingView: some View {
        ProgressView("Opening repository\u{2026}")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Error View

    private func errorView(message: String) -> some View {
        ContentUnavailableView(
            "Cannot Open Repository",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }
}

// MARK: - RepositoryWindowContent

/// Inner view that creates and owns all stable ViewModels.
///
/// Split from ``RepositoryWindowView`` so ViewModels are only instantiated
/// once a repository handle is available, and are held stable in `@State`.
private struct RepositoryWindowContent: View {

    let reference: RepositoryReference
    let repository: any GitRepositoryProtocol

    // MARK: State — stable ViewModels

    @State private var sidebarVM: SidebarViewModel
    @State private var historyVM: HistoryViewModel
    @State private var stashesVM: StashesViewModel
    @State private var reflogVM: ReflogViewModel
    @State private var branchesReviewVM: BranchesReviewViewModel
    @State private var pullRequestsVM: PullRequestsViewModel
    @State private var toolbarState = RepositoryToolbarState()

    /// Sidebar-driven navigation selection.
    @State private var selectedItem: SidebarItem = .workingCopy

    /// File system watcher for live refresh when files change on disk.
    @State private var fileWatcher: FileWatcher?

    /// Undo/redo manager for reversible git operations.
    @State private var gitUndoManager: GitUndoManager

    /// Background auto-fetch scheduler.
    @State private var autoFetcher: AutoFetchScheduler

    // MARK: Init

    init(reference: RepositoryReference, repository: any GitRepositoryProtocol) {
        self.reference = reference
        self.repository = repository
        _sidebarVM         = State(wrappedValue: SidebarViewModel(repository: repository))
        _historyVM         = State(wrappedValue: HistoryViewModel(repository: repository))
        _stashesVM         = State(wrappedValue: StashesViewModel(repository: repository))
        _reflogVM          = State(wrappedValue: ReflogViewModel(repository: repository))
        _branchesReviewVM  = State(wrappedValue: BranchesReviewViewModel(repository: repository))
        _pullRequestsVM    = State(wrappedValue: PullRequestsViewModel(repository: repository))
        _gitUndoManager    = State(wrappedValue: GitUndoManager())
        _autoFetcher       = State(wrappedValue: AutoFetchScheduler(repository: repository))
    }

    // MARK: Body

    var body: some View {
        NavigationSplitView {
            RepositorySidebar()
                .environment(sidebarVM)
                .navigationSplitViewColumnWidth(min: 190, ideal: 230, max: 300)
        } detail: {
            contentView
                .safeAreaInset(edge: .bottom) {
                    StatusBarView(repository: repository, autoFetcher: autoFetcher)
                }
        }
        .onChange(of: sidebarVM.selection) { _, newItem in
            if let item = newItem {
                selectedItem = item
            }
        }
        .environment(gitUndoManager)
        .focusedValue(\.gitUndoManager, gitUndoManager)
        .repositoryToolbar(repository: repository, state: toolbarState)
        .navigationTitle(reference.displayName)
        .task {
            // Start watching the repository for filesystem changes.
            let watcher = FileWatcher(paths: [repository.path.path], latency: 1.0) { [weak sidebarVM] in
                guard let vm = sidebarVM else { return }
                Task { @MainActor in
                    await vm.refresh()
                }
            }
            watcher.start()
            fileWatcher = watcher
            // Initial sidebar load.
            await sidebarVM.refresh()
            // Start background auto-fetch.
            autoFetcher.start()
        }
        .onDisappear {
            fileWatcher?.stop()
            autoFetcher.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: GroveAction.notificationName)) { notification in
            guard let action = GroveAction(notification: notification) else { return }
            handleAction(action)
        }
    }

    // MARK: Action Handling

    private func handleAction(_ action: GroveAction) {
        switch action {
        case .navigateWorkingCopy:
            sidebarVM.selection = .workingCopy
        case .navigateHistory:
            sidebarVM.selection = .history
        case .navigateStashes:
            sidebarVM.selection = .stashes
        case .fetch:
            Task {
                toolbarState.remotes = (try? await repository.remotes()) ?? []
                toolbarState.isFetchPresented = true
            }
        case .pull:
            Task {
                toolbarState.remoteBranches = (try? await repository.remoteBranches()) ?? []
                toolbarState.remotes = (try? await repository.remotes()) ?? []
                toolbarState.isPullPresented = true
            }
        case .push:
            Task {
                toolbarState.localBranches = (try? await repository.localBranches()) ?? []
                toolbarState.remotes = (try? await repository.remotes()) ?? []
                toolbarState.isPushPresented = true
            }
        case .newBranch:
            Task {
                toolbarState.localBranches = (try? await repository.localBranches()) ?? []
                toolbarState.isBranchPresented = true
            }
        case .stash:
            toolbarState.isStashPresented = true
        case .merge:
            Task {
                toolbarState.localBranches = (try? await repository.localBranches()) ?? []
                toolbarState.isMergePresented = true
            }
        case .rebase:
            Task {
                toolbarState.localBranches = (try? await repository.localBranches()) ?? []
                toolbarState.isRebasePresented = true
            }
        case .commit:
            // Commit is handled by the WorkingCopyViewModel directly.
            break
        case .quickActions:
            // Quick Actions panel is handled elsewhere.
            break
        case .quickOpen:
            // Quick Open triggers the Quick Actions panel in filename mode.
            break
        case .navigateReflog:
            sidebarVM.selection = .reflog
        case .navigatePullRequests:
            sidebarVM.selection = .pullRequests
        case .navigateBranchesReview:
            sidebarVM.selection = .branchesReview
        case .undo:
            Task {
                do {
                    try await gitUndoManager.undo()
                    await sidebarVM.refresh()
                } catch {
                    gitUndoManager.errorMessage = error.localizedDescription
                }
            }
        case .redo:
            Task {
                do {
                    try await gitUndoManager.redo()
                    await sidebarVM.refresh()
                } catch {
                    gitUndoManager.errorMessage = error.localizedDescription
                }
            }
        }
    }

    // MARK: Content Routing

    @ViewBuilder
    private var contentView: some View {
        switch selectedItem {
        case .workingCopy:
            WorkingCopyView(repository: repository)

        case .history:
            HistoryView()
                .environment(historyVM)
                .task(id: "history-initial") {
                    await historyVM.loadInitial()
                }

        case .stashes:
            StashesView()
                .environment(stashesVM)
                .task(id: "stashes-initial") {
                    await stashesVM.refresh()
                }

        case .reflog:
            ReflogView()
                .environment(reflogVM)
                .task(id: "reflog-initial") {
                    await reflogVM.refresh()
                }

        case .blame:
            BlameFilePicker(repository: repository)

        case .pullRequests:
            PullRequestsView()
                .environment(pullRequestsVM)
                .task(id: "pullrequests-initial") {
                    await pullRequestsVM.refresh()
                }

        case .branchesReview:
            BranchesReviewView()
                .environment(branchesReviewVM)
                .task(id: "branchesreview-initial") {
                    await branchesReviewVM.refresh()
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

    /// History view filtered to a specific branch or tag.
    ///
    /// Creates a fresh HistoryViewModel scoped to the provided ref so that
    /// navigating to different branches doesn't mutate the shared history VM.
    private func filteredHistoryView(branch: String) -> some View {
        let filteredVM = HistoryViewModel(repository: repository)
        filteredVM.filterBranch = branch
        return HistoryView()
            .environment(filteredVM)
            .task(id: branch) {
                await filteredVM.loadInitial()
            }
    }

}

// MARK: - Preview

#Preview {
    RepositoryWindowView(
        reference: RepositoryReference(path: "/Users/dev/Projects/my-app")
    )
}
