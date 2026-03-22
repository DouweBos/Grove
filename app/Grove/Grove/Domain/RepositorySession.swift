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
    let historyVM: HistoryViewModel
    let stashesVM: StashesViewModel
    let reflogVM: ReflogViewModel
    let branchesReviewVM: BranchesReviewViewModel
    let pullRequestsVM: PullRequestsViewModel
    let toolbarState = RepositoryToolbarState()
    let gitUndoManager = GitUndoManager()
    let autoFetcher: AutoFetchScheduler

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
        self.historyVM        = HistoryViewModel(repository: repository)
        self.stashesVM        = StashesViewModel(repository: repository)
        self.reflogVM         = ReflogViewModel(repository: repository)
        self.branchesReviewVM = BranchesReviewViewModel(repository: repository)
        self.pullRequestsVM   = PullRequestsViewModel(repository: repository)
        self.autoFetcher      = AutoFetchScheduler(repository: repository)
    }

    // MARK: - Lifecycle

    /// Start watching the repository for filesystem changes and begin auto-fetch.
    func start() async {
        let watcher = FileWatcher(paths: [repository.path.path], latency: 1.0) { [weak self] in
            guard let vm = self?.sidebarVM else { return }
            Task { @MainActor in
                await vm.refresh()
            }
        }
        watcher.start()
        fileWatcher = watcher

        await sidebarVM.refresh()
        autoFetcher.start()
    }

    /// Stop the file watcher and auto-fetcher.
    func stop() {
        fileWatcher?.stop()
        autoFetcher.stop()
    }

    // MARK: - Action Handling

    func handleAction(_ action: GroveAction) {
        switch action {
        case .navigateWorkingCopy:
            sidebarVM.selection = .workingCopy
        case .navigateHistory:
            sidebarVM.selection = .history
        case .navigateStashes:
            sidebarVM.selection = .stashes
        case .navigateReflog:
            sidebarVM.selection = .reflog
        case .navigatePullRequests:
            sidebarVM.selection = .pullRequests
        case .navigateBranchesReview:
            sidebarVM.selection = .branchesReview
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
            break
        case .quickActions:
            break
        case .quickOpen:
            break
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

    // MARK: - Helpers

    /// Returns a history ViewModel filtered to a specific branch or tag,
    /// reusing cached instances so re-renders don't discard loaded data.
    func filteredHistoryVM(for branch: String) -> HistoryViewModel {
        if let existing = filteredHistoryVMs[branch] {
            return existing
        }
        let vm = HistoryViewModel(repository: repository)
        vm.filterBranch = branch
        filteredHistoryVMs[branch] = vm
        return vm
    }
}
