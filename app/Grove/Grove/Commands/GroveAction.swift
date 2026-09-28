// Commands/GroveAction.swift
// Grove
//
// Notification-based action bus used to bridge SwiftUI Commands
// (which have no direct access to RepositoryViewModel) to the
// currently-focused repository window.
//
// Sender: GroveCommands menu items post a Notification whose object is a GroveAction.
// Receiver: RootWindowHost observes GroveAction.notificationName and forwards
// the action to the active RepositorySession.

import Foundation

// MARK: - GroveAction

/// Every discrete user-triggered action that can originate from the menu bar.
///
/// Commands post these through ``GroveAction/post()`` and repository windows
/// receive them via ``GroveAction/notificationName``.
enum GroveAction: String, Sendable {

    // MARK: Repository Browser

    case addRepository
    case cloneRepository
    case createRepository
    case newGroup

    // MARK: Navigation

    /// Navigate to the Working Copy view (Cmd+1).
    case navigateWorkingCopy
    /// Navigate to the History view (Cmd+2).
    case navigateHistory
    /// Navigate to the Stashes view (Cmd+3).
    case navigateStashes
    /// Navigate to the Reflog view (Cmd+4).
    case navigateReflog
    /// Navigate to the Pull Requests view (Cmd+5).
    case navigatePullRequests
    /// Navigate to the Branches Review view (Cmd+6).
    case navigateBranchesReview
    /// Navigate to Blame (Cmd+7).
    case navigateBlame
    /// Navigate to Repository Settings (Cmd+8).
    case navigateSettings

    // MARK: Remote Operations

    /// Fetch from all remotes (Cmd+Shift+F).
    case fetch
    /// Show the Pull dialog (Cmd+Shift+P).
    case pull
    /// Show the Push dialog (Cmd+Shift+U).
    case push

    // MARK: Branch

    /// Show the New Branch dialog (Cmd+B).
    case newBranch

    // MARK: Commit

    /// Commit staged changes (Cmd+Return).
    case commit

    // MARK: Stash

    /// Show the Stash dialog (Cmd+Shift+S).
    case stash

    // MARK: Merge / Rebase

    /// Show the Merge dialog (Cmd+Shift+M).
    case merge
    /// Show the Rebase dialog (Cmd+Shift+R).
    case rebase

    // MARK: Quick Actions

    /// Toggle the Quick Actions command palette (Cmd+Shift+A).
    case quickActions
    /// Quick Open — the Quick Actions palette on its Files tab (Cmd+Shift+O).
    case quickOpen

    // MARK: Undo / Redo

    /// Undo the last recorded git operation (Cmd+Z).
    case undo
    /// Redo the last undone git operation (Cmd+Shift+Z).
    case redo

    // MARK: Notification Plumbing

    /// The `Notification.Name` observed by repository windows.
    static let notificationName = Notification.Name("com.grove.action")

    /// The `userInfo` key under which the raw action value is stored.
    static let userInfoKey = "action"

    /// Posts this action to the default `NotificationCenter`.
    ///
    /// Always dispatched on the main thread so receivers can safely
    /// update `@Observable` state without additional dispatch.
    func post() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: GroveAction.notificationName,
                object: nil,
                userInfo: [GroveAction.userInfoKey: self.rawValue]
            )
        }
    }

    /// Attempts to decode a ``GroveAction`` from a `Notification` posted by
    /// ``post()``.
    init?(notification: Notification) {
        guard
            let raw = notification.userInfo?[GroveAction.userInfoKey] as? String,
            let action = GroveAction(rawValue: raw)
        else { return nil }
        self = action
    }
}
