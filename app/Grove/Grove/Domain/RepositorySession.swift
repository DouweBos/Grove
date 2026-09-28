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
/// The window keeps a few sessions: `start()` when shown, `pause()` when left, `stop()` when evicted.
@MainActor
@Observable
final class RepositorySession {

    // MARK: - ViewModels

    /// One read of branches, tags and remotes per refresh, shared by every view below.
    let refs: RepositoryRefs
    let sidebarVM: SidebarViewModel
    let workingCopyVM: WorkingCopyViewModel
    let historyVM: HistoryViewModel
    let stashesVM: StashesViewModel
    let reflogVM: ReflogViewModel
    let branchesReviewVM: BranchesReviewViewModel
    let pullRequestsVM: PullRequestsViewModel
    let repositorySettingsVM: RepositorySettingsViewModel
    let toolbarState: RepositoryToolbarState
    let gitUndoManager = GitUndoManager()
    let autoFetcher: AutoFetchScheduler
    let blameVM: BlameViewModel

    // MARK: - Navigation

    /// Sidebar-driven navigation selection.
    var selectedItem: SidebarItem = .workingCopy

    /// Cached filtered history ViewModels keyed by ref name; see RepositorySession+Refresh.
    var filteredHistoryVMs: [String: HistoryViewModel] = [:]
    /// Ref names of `filteredHistoryVMs`, least recently shown first.
    var filteredHistoryOrder: [String] = []

    // MARK: - Refresh State

    /// Bumped by every `refreshAll()`; a tab refreshed at the current value is up to date.
    private(set) var refreshGeneration = 0
    var tabRefreshes: [RefreshedTab: TabRefresh] = [:]
    private var isRefreshing = false
    private var needsAnotherRefresh = false

    // MARK: - Private

    let repository: any GitRepositoryProtocol
    private var fileWatcher: FileWatcher?
    /// False while paused: nothing watches or fetches, but every loaded list stays.
    private(set) var isActive = false

    // MARK: - Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
        let refs = RepositoryRefs(repository: repository, readsStatus: false)
        self.refs = refs
        self.sidebarVM        = SidebarViewModel(repository: repository, refs: refs)
        self.workingCopyVM    = WorkingCopyViewModel(repository: repository)
        self.historyVM        = HistoryViewModel(repository: repository, refs: refs)
        self.stashesVM        = StashesViewModel(repository: repository)
        self.reflogVM         = ReflogViewModel(repository: repository)
        self.branchesReviewVM = BranchesReviewViewModel(repository: repository, refs: refs)
        self.pullRequestsVM   = PullRequestsViewModel(repository: repository)
        self.toolbarState     = RepositoryToolbarState(refs: refs)
        self.repositorySettingsVM = RepositorySettingsViewModel(repository: repository)
        self.autoFetcher      = AutoFetchScheduler(repository: repository)
        self.blameVM          = BlameViewModel(repository: repository)
        wireFeatureViewModels()
    }

    /// Lets feature VMs refresh the whole session and record undoable actions.
    private func wireFeatureViewModels() {
        let refresh: () async -> Void = { [weak self] in await self?.refreshAll() }
        sidebarVM.onRepositoryChanged = refresh
        sidebarVM.changeCountSource = { [workingCopyVM] in workingCopyVM.changedCount }
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

    /// Watches the repository, starts auto-fetch and refreshes; lists loaded before a pause stay visible meanwhile.
    func start() async {
        guard !isActive else { return }
        isActive = true
        let watcher = FileWatcher(paths: [repository.path.path], latency: 1.0) { [weak self] in
            Task { @MainActor in
                guard let self, self.isActive else { return }
                await self.refreshAll()
            }
        }
        watcher.start()
        fileWatcher = watcher
        autoFetcher.start()
        await refreshAll()
    }

    /// Leaving the repository: stops watching and fetching but keeps every loaded list for a quick return.
    func pause() {
        guard isActive else { return }
        isActive = false
        fileWatcher?.stop()
        fileWatcher = nil
        autoFetcher.stop()
    }

    /// Stop the file watcher and auto-fetcher for good, e.g. when the session is evicted.
    func stop() {
        pause()
    }

    /// Reload everything that reflects repository state. Only what's on screen reloads now;
    /// hidden history lists and tabs are marked stale and reload when shown.
    func refreshAll() async {
        guard !isRefreshing else { return needsAnotherRefresh = true }
        isRefreshing = true
        defer { isRefreshing = false }
        repeat {
            needsAnotherRefresh = false
            refreshGeneration += 1
            let visible = visibleHistoryVM
            for vm in [historyVM] + Array(filteredHistoryVMs.values) where vm !== visible { vm.markStale() }
            // Started first so the history list and Branches Review join this read instead of their own.
            let refsRead = refs.beginRefresh()
            async let workingCopy: Void = workingCopyVM.refresh()
            async let history: Void = reload(visible)
            async let tab: Void = refreshSelectedTab()
            _ = await (refsRead.value, workingCopy, history, tab)
        } while needsAnotherRefresh
    }

    private func reload(_ vm: HistoryViewModel?) async {
        await vm?.reload()
    }

    // MARK: - Action Handling

    // swiftlint:disable:next cyclomatic_complexity
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
            toolbarState.present(.fetch)
        case .pull:
            toolbarState.present(.pull)
        case .push:
            toolbarState.present(.push)
        case .newBranch:
            toolbarState.present(.branch)
        case .stash:
            toolbarState.present(.stash)
        case .merge:
            toolbarState.present(.merge)
        case .rebase:
            toolbarState.present(.rebase)
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
}
