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
    /// Leave the open repository and list local repositories (the disk button).
    case showLocalRepositories
    /// Leave the open repository and list the GitHub account's repositories (the cloud button).
    case showRemoteRepositories
    /// Open the sidebar title's repository switcher (Cmd+Option+O).
    case switchRepository
    /// Back / forward through the window's navigation history (Cmd-[ / Cmd-], mouse buttons 4 and 5).
    case navigateBack
    case navigateForward

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
    /// Navigate to the Stack view (Cmd+9).
    case navigateStack
    /// Navigate to Blame (Cmd+7).
    case navigateBlame
    /// Navigate to Repository Settings (Cmd+8).
    case navigateSettings
    /// Navigate to the Actions view (Cmd+9).
    case navigateCI

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
    /// Show the Save Snapshot dialog: a stash that leaves the working copy alone.
    case saveSnapshot

    // MARK: Patches

    /// Choose a patch file and apply it to the working copy.
    case applyPatch

    // MARK: Merge / Rebase

    /// Show the Merge dialog (Cmd+Shift+M).
    case merge
    /// Show the Rebase dialog (Cmd+Shift+R).
    case rebase

    // MARK: Pull Requests

    /// Show the Create Pull Request sheet for the checked-out branch.
    case createPullRequest

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
