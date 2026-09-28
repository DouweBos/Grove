// Views/Repositories/WindowViewModel+History.swift
// Grove
//
// Back / forward through where the window has been: the browsers, and repositories with their tab.

import Foundation

/// A place the window can show.
enum NavigationLocation: Equatable {
    case browser(WindowViewModel.BrowserMode)
    /// `item` is nil while the repository is still opening.
    case repository(path: String, item: SidebarItem?)

    /// Same place, ignoring a tab that isn't known yet.
    func matches(_ other: NavigationLocation) -> Bool {
        switch (self, other) {
        case (.browser(let lhs), .browser(let rhs)): lhs == rhs
        case (.repository(let lhsPath, let lhsItem), .repository(let rhsPath, let rhsItem)):
            lhsPath == rhsPath && (lhsItem == nil || rhsItem == nil || lhsItem == rhsItem)
        default: false
        }
    }
}

extension WindowViewModel {

    var currentLocation: NavigationLocation {
        guard let openRepo else { return .browser(browserMode) }
        return .repository(path: openRepo.path, item: currentSession?.session.selectedItem)
    }

    var canGoBack: Bool { !backHistory.isEmpty }
    var canGoForward: Bool { !forwardHistory.isEmpty }

    func goBack() {
        guard let target = backHistory.last else { return }
        popBack()
        pushForward(currentLocation)
        apply(target)
    }

    func goForward() {
        guard let target = forwardHistory.last else { return }
        popForward()
        pushBack(currentLocation)
        apply(target)
    }

    /// Called before a user action moves the window to `target`; a new step clears forward history.
    func recordNavigation(to target: NavigationLocation) {
        guard !isApplyingHistory, !currentLocation.matches(target) else { return }
        let current = currentLocation
        if backHistory.last.map({ $0 == current }) != true { pushBack(current) }
        clearForward()
    }

    private func apply(_ location: NavigationLocation) {
        withHistoryApplying {
            switch location {
            case .browser(.local):
                showLocalRepositories()
            case .browser(.remote):
                showRemoteRepositories()
            case .repository(let path, let item):
                if openRepo?.path == path {
                    if let item { currentSession?.session.restoreSelection(item) }
                } else {
                    reopen(path: path, on: item)
                }
            }
        }
    }
}
