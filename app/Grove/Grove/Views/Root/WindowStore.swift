// Views/Root/WindowStore.swift
// Grove
//
// Hands each window its WindowViewModel and keeps closed windows' models alive.

import Foundation
import Observation

/// App-wide owner of window state: a closed window's sessions keep fetching in the background,
/// and the next window opened with none left on screen picks up where it left off.
@MainActor
@Observable
final class WindowStore {

    let manager: any RepositoryManagerProtocol
    private var openWindows: [WindowViewModel] = []
    /// Most recently closed last; only these few keep fetching.
    private var closedWindows: [WindowViewModel] = []
    private var hasHandledLaunchArguments = false
    static let closedWindowLimit = 3

    init(manager: any RepositoryManagerProtocol) {
        self.manager = manager
    }

    /// A model for a window that just opened: the last closed one when no window is on screen,
    /// else a fresh one. `reference` opens that repository in it.
    func claimWindow(opening reference: RepositoryReference?) -> WindowViewModel {
        let window = openWindows.isEmpty && reference == nil
            ? closedWindows.popLast() ?? WindowViewModel(manager: manager)
            : WindowViewModel(manager: manager)
        openWindows.append(window)
        if let reference, window.openRepo != reference { window.openReference(reference) }
        return window
    }

    func windowClosed(_ window: WindowViewModel) {
        openWindows.removeAll { $0 === window }
        window.pauseCurrentSession()
        closedWindows.append(window)
        while closedWindows.count > Self.closedWindowLimit {
            closedWindows.removeFirst().stopSessions()
        }
    }

    func windowReappeared(_ window: WindowViewModel) {
        closedWindows.removeAll { $0 === window }
        if !openWindows.contains(where: { $0 === window }) { openWindows.append(window) }
    }

    /// Dev launch flags apply to the first window only, not to every restored one.
    func consumeLaunchArguments() -> Bool {
        defer { hasHandledLaunchArguments = true }
        return !hasHandledLaunchArguments
    }
}
