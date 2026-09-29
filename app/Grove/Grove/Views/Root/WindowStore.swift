// Views/Root/WindowStore.swift
// Grove
//
// Hands each window its WindowViewModel and keeps closed windows' models alive.

import AppKit
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
    /// The window a requested tab should join, and when it was asked for; stale requests are dropped.
    private var pendingTab: (parent: NSWindow, requested: Date)?
    /// Run by the next window to open, for dock menu actions with no window on screen.
    private var pendingAction: GroveAction?
    private weak var lastKeyWindow: WindowViewModel?
    /// Opens a Grove window; set by the first window, since only views can reach `openWindow`.
    static var newTabHandler: (() -> Void)?
    /// Opens a repository in a new tab of the key window; set alongside `newTabHandler`.
    static var openTabHandler: ((RepositoryReference) -> Void)?
    /// Opens a standalone Grove window; set alongside `newTabHandler`.
    static var newWindowHandler: (() -> Void)?
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
        window.onWorktreeRemoved = { [weak self] path, main in self?.worktreeRemoved(at: path, mainRepositoryPath: main) }
        if let reference, window.openRepo != reference { window.openReference(reference) }
        if let pendingAction {
            self.pendingAction = nil
            _ = window.handleBrowserAction(pendingAction)
        }
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

    /// Every window lets go of a removed worktree. A tab showing it closes when another already shows
    /// the main repository, and otherwise moves there.
    func worktreeRemoved(at path: String, mainRepositoryPath main: String?) {
        if let main {
            for window in openWindows where window.isShowing(path: path)
                && openWindows.contains(where: { $0 !== window && $0.isShowing(path: main) }) {
                window.closeWindow?()
            }
        }
        for window in openWindows + closedWindows {
            window.forgetWorktree(at: path, mainRepositoryPath: main)
        }
    }

    func windowBecameKey(_ window: WindowViewModel) {
        lastKeyWindow = window
    }

    /// Runs a browser action from outside any window: in the last key window, else in a new one.
    func perform(_ action: GroveAction) {
        NSApp.activate()
        if let window = lastKeyWindow.flatMap({ last in openWindows.first { $0 === last } }) ?? openWindows.last {
            _ = window.handleBrowserAction(action)
        } else {
            pendingAction = action
            Self.newWindowHandler?()
        }
    }

    /// The next Grove window to appear joins `parent` (the key window by default) as a tab.
    func requestTab(in parent: NSWindow? = NSApp.keyWindow) {
        pendingTab = parent.map { ($0, Date()) }
    }

    func attach(_ window: NSWindow) {
        window.tabbingIdentifier = Self.tabbingIdentifier
        guard let pending = pendingTab else { return }
        pendingTab = nil
        // openWindow on a repository already on screen focuses it instead of opening one.
        guard pending.parent !== window, Date().timeIntervalSince(pending.requested) < 2 else { return }
        pending.parent.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
    }

    /// Dev launch flags apply to the first window only, not to every restored one.
    func consumeLaunchArguments() -> Bool {
        defer { hasHandledLaunchArguments = true }
        return !hasHandledLaunchArguments
    }
}
