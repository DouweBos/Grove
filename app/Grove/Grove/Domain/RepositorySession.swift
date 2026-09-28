// Domain/RepositorySession.swift
// Grove
//
// Owns all per-repository ViewModels and coordination state for a single
// open repository. RootWindowHost caches one session per repo path.

import Foundation
import Observation
import os

// MARK: - RepositorySession

/// Bundles every ViewModel and service needed while a repository window is open.
///
/// The view creates a single `@State` session and calls `start()` / `stop()`
/// in `.task` / `.onDisappear`.
@MainActor
@Observable
final class RepositorySession {

    // MARK: - ViewModels

    let sidebarVM: SidebarViewModel
    let workingCopyVM: WorkingCopyViewModel
    let historyVM: HistoryViewModel
    let stashesVM: StashesViewModel
    let reflogVM: ReflogViewModel
    let branchesReviewVM: BranchesReviewViewModel
    let pullRequestsVM: PullRequestsViewModel
    let repositorySettingsVM: RepositorySettingsViewModel
    let toolbarState = RepositoryToolbarState()
    let gitUndoManager = GitUndoManager()
    let autoFetcher: AutoFetchScheduler
    let blameVM: BlameViewModel

    // MARK: - Navigation

    /// Sidebar-driven navigation selection.
    var selectedItem: SidebarItem = .workingCopy

    /// Cached filtered history ViewModels keyed by ref name.
    var filteredHistoryVMs: [String: HistoryViewModel] = [:]

    // MARK: - Private

    let repository: any GitRepositoryProtocol
    private var fileWatcher: FileWatcher?

    // MARK: - Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
        self.sidebarVM        = SidebarViewModel(repository: repository)
        self.workingCopyVM    = WorkingCopyViewModel(repository: repository)
        self.historyVM        = HistoryViewModel(repository: repository)
        self.stashesVM        = StashesViewModel(repository: repository)
        self.reflogVM         = ReflogViewModel(repository: repository)
        self.branchesReviewVM = BranchesReviewViewModel(repository: repository)
        self.pullRequestsVM   = PullRequestsViewModel(repository: repository)
        self.repositorySettingsVM = RepositorySettingsViewModel(repository: repository)
        self.autoFetcher      = AutoFetchScheduler(repository: repository)
        self.blameVM          = BlameViewModel(repository: repository)
        wireFeatureViewModels()
    }

    /// Lets feature VMs refresh the whole session and record undoable actions.
    private func wireFeatureViewModels() {
        let refresh: () async -> Void = { [weak self] in await self?.refreshAll() }
        sidebarVM.onRepositoryChanged = refresh
        sidebarVM.undoManager = gitUndoManager
        workingCopyVM.onRepositoryChanged = refresh
        workingCopyVM.undoManager = gitUndoManager
        historyVM.onRepositoryChanged = refresh
        historyVM.undoManager = gitUndoManager
        stashesVM.onRepositoryChanged = refresh
        reflogVM.onRepositoryChanged = refresh
        reflogVM.undoManager = gitUndoManager
        branchesReviewVM.onRepositoryChanged = refresh
        branchesReviewVM.undoManager = gitUndoManager
        pullRequestsVM.onRepositoryChanged = refresh
    }

    // MARK: - Lifecycle

    /// Start watching the repository for filesystem changes and begin auto-fetch.
    func start() async {
        let watcher = FileWatcher(paths: [repository.path.path], latency: 1.0) { [weak self] in
            Task { @MainActor in
                await self?.refreshAll()
            }
        }
        watcher.start()
        fileWatcher = watcher

        await sidebarVM.refresh()
        await workingCopyVM.refresh()
        autoFetcher.start()
    }

    /// Reload everything that reflects repository state. Views that were never
    /// opened stay unloaded; loaded lists refresh in place.
    func refreshAll() async {
        guard !isRefreshing else { return needsAnotherRefresh = true }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            needsAnotherRefresh = false
            async let sidebar: Void = sidebarVM.refresh()
            async let workingCopy: Void = workingCopyVM.refresh()
            async let history: Void = historyVM.reload()
            _ = await (sidebar, workingCopy, history)
            for vm in filteredHistoryVMs.values { await vm.reload() }
            if !stashesVM.stashes.isEmpty || selectedItem == .stashes { await stashesVM.refresh() }
            if selectedItem == .reflog { await reflogVM.refresh() }
            if selectedItem == .branchesReview { await branchesReviewVM.refresh() }
        } while needsAnotherRefresh
    }

    private var isRefreshing = false
    private var needsAnotherRefresh = false

    /// Stop the file watcher and auto-fetcher.
    func stop() {
        fileWatcher?.stop()
        autoFetcher.stop()
    }

    // MARK: - Action Handling

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func handleAction(_ action: GroveAction) {
        switch action {
        case .navigateWorkingCopy:
            sidebarVM.select(.workingCopy)
        case .navigateHistory:
            sidebarVM.select(.history)
        case .navigateStashes:
            sidebarVM.select(.stashes)
        case .navigateReflog:
            sidebarVM.select(.reflog)
        case .navigatePullRequests:
            sidebarVM.select(.pullRequests)
        case .navigateBranchesReview:
            sidebarVM.select(.branchesReview)
        case .navigateBlame:
            sidebarVM.select(.blame)
        case .navigateSettings:
            sidebarVM.select(.settings)
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
            guard selectedItem == .workingCopy else { return }
            Task { await workingCopyVM.commit() }
        case .quickActions, .quickOpen:
            break
        case .addRepository, .cloneRepository, .createRepository, .newGroup, .showLocalRepositories, .showRemoteRepositories,
             .navigateBack, .navigateForward:
            break
        case .undo:
            Task {
                do {
                    try await gitUndoManager.undo()
                    await refreshAll()
                } catch {
                    // A grouped action may have partly applied before failing.
                    gitUndoManager.reportError(error)
                    await refreshAll()
                }
            }
        case .redo:
            Task {
                do {
                    try await gitUndoManager.redo()
                    await refreshAll()
                } catch {
                    gitUndoManager.reportError(error, redo: true)
                    await refreshAll()
                }
            }
        }
    }

    /// Opens on `item` instead of Changes, e.g. to keep the tab when switching worktrees.
    func restoreSelection(_ item: SidebarItem) {
        sidebarVM.select(item)
        selectedItem = item
    }

    // MARK: - Helpers

    /// Returns a history ViewModel filtered to a specific branch or tag,
    /// reusing cached instances so re-renders don't discard loaded data.
    func filteredHistoryVM(for branch: String) -> HistoryViewModel {
        if let existing = filteredHistoryVMs[branch] {
            return existing
        }
        let vm = HistoryViewModel(repository: repository)
        vm.filterBranch = branch
        vm.onRepositoryChanged = { [weak self] in await self?.refreshAll() }
        filteredHistoryVMs[branch] = vm
        return vm
    }
}
