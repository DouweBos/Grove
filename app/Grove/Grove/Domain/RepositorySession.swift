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
    let stackVM: StackViewModel
    let pullRequestsVM: PullRequestsViewModel
    let ciVM: CIViewModel
    let repositorySettingsVM: RepositorySettingsViewModel
    let toolbarState: RepositoryToolbarState
    let gitUndoManager = GitUndoManager()
    let autoFetcher: AutoFetchScheduler
    let blameVM: BlameViewModel
    let gitFlowVM: GitFlowViewModel
    let svnVM: SVNViewModel

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
    /// Set by the window: the folder was deleted outside Grove. Passes its path and, for a worktree, its main repository.
    var onFolderRemoved: ((String, String?) -> Void)?
    /// Read up front: a deleted worktree can no longer say which repository it belonged to.
    private let mainRepositoryPath: String?

    // MARK: - Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
        self.mainRepositoryPath = WorktreeResolver.mainRepositoryPath(forWorktreeAt: repository.path.path)
        let refs = RepositoryRefs(repository: repository, readsStatus: false)
        self.refs = refs
        self.sidebarVM        = SidebarViewModel(repository: repository, refs: refs)
        self.workingCopyVM    = WorkingCopyViewModel(repository: repository)
        self.historyVM        = HistoryViewModel(repository: repository, refs: refs)
        self.stashesVM        = StashesViewModel(repository: repository)
        self.reflogVM         = ReflogViewModel(repository: repository)
        self.branchesReviewVM = BranchesReviewViewModel(repository: repository, refs: refs)
        self.stackVM          = StackViewModel(repository: repository, refs: refs)
        self.pullRequestsVM   = PullRequestsViewModel(repository: repository, refs: refs)
        self.ciVM             = CIViewModel(repository: repository, refs: refs)
        let gitFlowVM = GitFlowViewModel(repository: repository, refs: refs)
        let svnVM = SVNViewModel(repository: repository)
        self.gitFlowVM        = gitFlowVM
        self.svnVM            = svnVM
        self.toolbarState     = RepositoryToolbarState(refs: refs, gitFlow: gitFlowVM, svn: svnVM)
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
        historyVM.onRebaseStopped = { [weak self] in self?.sidebarVM.select(.workingCopy) }
        sidebarVM.onRevealInHistory = { [weak self] sha, fallback in Task { await self?.revealInHistory(sha, fallback: fallback) } }
        stashesVM.onRevealInHistory = { [weak self] sha in Task { await self?.revealInHistory(sha) } }
        stashesVM.onRepositoryChanged = refresh
        reflogVM.onRepositoryChanged = refresh
        reflogVM.undoManager = gitUndoManager
        branchesReviewVM.onRepositoryChanged = refresh
        branchesReviewVM.undoManager = gitUndoManager
        pullRequestsVM.onRepositoryChanged = refresh
        stackVM.onRepositoryChanged = refresh
        stackVM.onRestackStopped = { [weak self] in self?.sidebarVM.select(.workingCopy) }
        stackVM.onCreatePullRequest = { [weak self] branch in self?.pullRequestsVM.beginCreatePullRequest(head: branch) }
        stackVM.onShowStack = { [weak self] id in self?.sidebarVM.select(.branchStack(id)) }
        gitFlowVM.onRepositoryChanged = refresh
        svnVM.onRepositoryChanged = refresh
        sidebarVM.gitFlow = gitFlowVM
        toolbarState.onAddSubmodule = { [sidebarVM] in sidebarVM.requestAddSubmodule() }
        toolbarState.onAddRemote = { [sidebarVM] in sidebarVM.requestAddRemote() }
        repositorySettingsVM.onAddRemote = { [sidebarVM] in sidebarVM.requestAddRemote() }
        repositorySettingsVM.onRepositoryChanged = refresh
        pullRequestsVM.onShowPullRequests = { [weak self] in self?.sidebarVM.select(.pullRequests) }
        ciVM.onShowCI = { [weak self] in self?.sidebarVM.select(.ci) }
        ciVM.watcher.setRevealHandler(for: ciVM.repositoryPath) { [weak self] runID in
            self?.sidebarVM.select(.ci)
            Task { await self?.ciVM.reveal(runID: runID) }
        }
        sidebarVM.onShowRuns = { [weak self] branch in
            self?.sidebarVM.select(.ci)
            Task { await self?.ciVM.showRuns(for: branch) }
        }
        sidebarVM.onCreatePullRequest = { [weak self] branch in self?.pullRequestsVM.beginCreatePullRequest(head: branch) }
    }

    // MARK: - Lifecycle

    /// Watches the repository, starts auto-fetch and refreshes; lists loaded before a pause stay visible meanwhile.
    func start() async {
        guard !isActive else { return }
        isActive = true
        let watcher = FileWatcher(paths: [repository.path.path], latency: 1.0) { [weak self] in
            Task { @MainActor in await self?.folderChanged() }
        }
        watcher.start()
        fileWatcher = watcher
        autoFetcher.start()
        await refreshAll()
    }

    /// A watched change: refreshes, or hands the session back when the folder itself is gone.
    func folderChanged() async {
        guard isActive else { return }
        let path = repository.path.path
        guard FileManager.default.fileExists(atPath: path) else {
            stop()
            onFolderRemoved?(path, mainRepositoryPath)
            return
        }
        await refreshAll()
    }

    /// Leaving the repository: stops watching but keeps fetching in the background, and keeps every loaded list.
    func pause() {
        guard isActive else { return }
        isActive = false
        fileWatcher?.stop()
        fileWatcher = nil
    }

    /// Stop the file watcher and auto-fetcher for good, e.g. when the session is evicted.
    func stop() {
        pause()
        autoFetcher.stop()
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
            async let flow: Void = gitFlowVM.refresh()
            async let svn: Void = svnVM.refresh()
            _ = await (refsRead.value, workingCopy, history, tab, flow, svn)
        } while needsAnotherRefresh
    }

    private func reload(_ vm: HistoryViewModel?) async {
        await vm?.reload()
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
        case .navigateCI:
            sidebarVM.select(.ci)
        case .navigateBranchesReview:
            sidebarVM.select(.branchesReview)
        case .navigateStack:
            sidebarVM.select(.stack)
        case .navigateBlame:
            sidebarVM.select(.blame)
        case .navigateSettings:
            sidebarVM.select(.settings)
        case .fetch:
            toolbarState.present(.fetch)
        case .pull:
            if svnVM.status.isSVN { svnVM.present(.fetch) } else { toolbarState.present(.pull) }
        case .push:
            if svnVM.status.isSVN { svnVM.present(.dcommit) } else { toolbarState.present(.push) }
        case .newBranch:
            toolbarState.present(.branch)
        case .stash:
            toolbarState.present(.stash)
        case .saveSnapshot:
            toolbarState.present(.snapshot)
        case .applyPatch:
            sidebarVM.select(.workingCopy)
            workingCopyVM.requestPatchFile()
        case .merge:
            toolbarState.present(.merge)
        case .rebase:
            toolbarState.present(.rebase)
        case .createPullRequest:
            pullRequestsVM.beginCreatePullRequest()
        case .runWorkflow:
            ciVM.beginDispatch()
        case .commit:
            guard selectedItem == .workingCopy else { return }
            Task { await workingCopyVM.commit() }
        case .quickActions, .quickOpen:
            break
        case .addRepository, .cloneRepository, .createRepository, .newGroup, .showLocalRepositories, .showRemoteRepositories, .switchRepository,
             .navigateBack, .navigateForward:
            break
        case .undo:
            Task { await runUndo(redo: false) }
        case .redo:
            Task { await runUndo(redo: true) }
        }
    }

    /// Selects `sha` in History when HEAD's history has it; otherwise opens `fallback`, e.g. a ref's own history.
    func revealInHistory(_ sha: String, fallback: SidebarItem? = nil) async {
        if await historyVM.contains(sha) || fallback == nil {
            sidebarVM.select(.history)
            await historyVM.reveal(sha)
        } else if let fallback {
            sidebarVM.select(fallback)
        }
    }

    private func runUndo(redo: Bool) async {
        do {
            if redo { try await gitUndoManager.redo() } else { try await gitUndoManager.undo() }
        } catch {
            // A grouped action may have partly applied before failing.
            gitUndoManager.reportError(error, redo: redo)
        }
        await refreshAll()
    }

    /// Back within the shown tab, taken before the window's own history: from a run's job to its summary.
    var canGoBackWithinTab: Bool { selectedItem == .ci && ciVM.detail.canReturnToSummary }

    func goBackWithinTab() {
        guard canGoBackWithinTab else { return }
        Task { await ciVM.detail.showSummary() }
    }

    /// Opens on `item` instead of Changes, e.g. to keep the tab when switching worktrees.
    func restoreSelection(_ item: SidebarItem) {
        sidebarVM.select(item)
        selectedItem = item
    }
}
