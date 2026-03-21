// Commands/GroveTabAction.swift
// Grove
//
// Notification-based action bus for tab management commands.
// Mirrors the GroveAction pattern so that Commands (which live outside
// the SwiftUI environment) can drive tab state in the focused window.

import Foundation

// MARK: - GroveTabAction

/// Tab lifecycle actions dispatched through NotificationCenter.
///
/// Commands post via ``post()``. The active repository window receives
/// them via ``notificationName`` and delegates to its
/// ``RepositoryWindowManager``.
enum GroveTabAction: String, Sendable {

    // MARK: Cases

    /// Open a new tab in the focused repository window (Cmd+T).
    case newTab
    /// Close the active tab; close the window when it is the last tab (Cmd+W).
    case closeTab
    /// Close the window unconditionally (last tab was closed).
    case closeWindow
    /// Select the next tab to the right, wrapping (Cmd+Shift+]).
    case nextTab
    /// Select the next tab to the left, wrapping (Cmd+Shift+[).
    case previousTab

    // MARK: Notification Plumbing

    /// The `Notification.Name` observed by repository windows.
    static let notificationName = Notification.Name("com.grove.tab-action")

    /// The `userInfo` key storing the raw action string.
    static let userInfoKey = "tab-action"

    /// Posts this action to the default `NotificationCenter` on the main thread.
    func post() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: GroveTabAction.notificationName,
                object: nil,
                userInfo: [GroveTabAction.userInfoKey: self.rawValue]
            )
        }
    }

    /// Attempts to decode a ``GroveTabAction`` from a `Notification`.
    init?(notification: Notification) {
        guard
            let raw = notification.userInfo?[GroveTabAction.userInfoKey] as? String,
            let action = GroveTabAction(rawValue: raw)
        else { return nil }
        self = action
    }
}
