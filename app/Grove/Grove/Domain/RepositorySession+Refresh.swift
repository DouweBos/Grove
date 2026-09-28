// Domain/RepositorySession+Refresh.swift
// Grove
//
// What a refresh reloads: the history list and tab on screen now, everything else when it's shown again.

import Foundation

/// Tabs whose lists load on entry rather than with every refresh.
enum RefreshedTab: Hashable {
    case stashes, reflog, pullRequests, branchesReview

    init?(_ item: SidebarItem) {
        switch item {
        case .stashes: self = .stashes
        case .reflog: self = .reflog
        case .pullRequests: self = .pullRequests
        case .branchesReview: self = .branchesReview
        default: return nil
        }
    }
}

/// When a tab's list was last read.
struct TabRefresh {
    let generation: Int
    let date: Date
}

extension RepositorySession {

    /// Filtered history lists kept at once; older ones are dropped and reload if reopened.
    static let filteredHistoryLimit = 8
    /// Pull requests live on the host, which the file watcher can't see, so they go stale by time.
    static let remoteTabLifetime: TimeInterval = 30

    // MARK: - History

    /// The history list on screen, if any.
    var visibleHistoryVM: HistoryViewModel? {
        switch selectedItem {
        case .history: historyVM
        case .branch(let info), .remoteBranch(let info): filteredHistoryVMs[info.name]
        case .tag(let info): filteredHistoryVMs[info.name]
        default: nil
        }
    }

    /// Returns a history ViewModel filtered to a specific branch or tag,
    /// reusing cached instances so re-renders don't discard loaded data.
    func filteredHistoryVM(for branch: String) -> HistoryViewModel {
        // Called from view bodies, so it only writes observed state when the order actually changes.
        if filteredHistoryOrder.last != branch {
            filteredHistoryOrder.removeAll { $0 == branch }
            filteredHistoryOrder.append(branch)
        }
        if let existing = filteredHistoryVMs[branch] { return existing }
        let vm = HistoryViewModel(repository: repository, refs: refs)
        vm.filterBranch = branch
        vm.onRepositoryChanged = { [weak self] in await self?.refreshAll() }
        vm.undoManager = gitUndoManager
        filteredHistoryVMs[branch] = vm
        while filteredHistoryOrder.count > Self.filteredHistoryLimit {
            filteredHistoryVMs[filteredHistoryOrder.removeFirst()] = nil
        }
        return vm
    }

    // MARK: - Tabs

    /// Tab entry: reads the tab's list unless it's still current, so switching back and forth doesn't re-read.
    func refreshOnEntry(_ item: SidebarItem) async {
        guard let tab = RefreshedTab(item), needsRefresh(tab) else { return }
        await refresh(tab)
    }

    func needsRefresh(_ tab: RefreshedTab) -> Bool {
        guard let last = tabRefreshes[tab] else { return true }
        if tab == .pullRequests { return Date().timeIntervalSince(last.date) > Self.remoteTabLifetime }
        return last.generation != refreshGeneration
    }

    /// Part of `refreshAll()`: the tab on screen, plus stashes when any exist, since their count shows elsewhere.
    func refreshSelectedTab() async {
        if !stashesVM.stashes.isEmpty, selectedItem != .stashes { await refresh(.stashes) }
        guard let tab = RefreshedTab(selectedItem), tab != .pullRequests else { return }
        await refresh(tab)
    }

    private func refresh(_ tab: RefreshedTab) async {
        tabRefreshes[tab] = TabRefresh(generation: refreshGeneration, date: Date())
        switch tab {
        case .stashes: await stashesVM.refresh()
        case .reflog: await reflogVM.refresh()
        case .pullRequests: await pullRequestsVM.refresh()
        case .branchesReview: await branchesReviewVM.refresh()
        }
    }
}
