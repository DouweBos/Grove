// Commands/GroveCommands.swift
// Grove
//
// SwiftUI Commands structs that register Grove's full menu-bar keyboard
// shortcut surface.
//
// Commands cannot directly access RepositoryViewModel because they live
// outside the SwiftUI environment hierarchy. Instead every action is
// dispatched through GroveAction.post(), which posts a Notification that
// the active RepositoryWindowView observes and handles.

import SwiftUI

// MARK: - GroveCommands

/// Aggregates all Grove menu-bar command groups into a single Commands value.
///
/// Add to a `Scene` via `.commands { GroveCommands() }`.
struct GroveCommands: Commands {

    // MARK: Body

    var body: some Commands {
        GroveNavigateCommands()
        GroveGitCommands()
    }
}

// MARK: - GroveNavigateCommands

/// Adds a **Navigate** menu with shortcuts to switch the active sidebar item.
private struct GroveNavigateCommands: Commands {

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Working Copy") {
                GroveAction.navigateWorkingCopy.post()
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("History") {
                GroveAction.navigateHistory.post()
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Stashes") {
                GroveAction.navigateStashes.post()
            }
            .keyboardShortcut("3", modifiers: .command)
        }
    }
}

// MARK: - GroveGitCommands

/// Adds a **Git** menu with shortcuts for the most common repository operations.
private struct GroveGitCommands: Commands {

    var body: some Commands {
        CommandMenu("Git") {

            // MARK: Remote

            Button("Fetch") {
                GroveAction.fetch.post()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Pull\u{2026}") {
                GroveAction.pull.post()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Push\u{2026}") {
                GroveAction.push.post()
            }
            .keyboardShortcut("u", modifiers: [.command, .shift])

            Divider()

            // MARK: Branch

            Button("New Branch\u{2026}") {
                GroveAction.newBranch.post()
            }
            .keyboardShortcut("b", modifiers: .command)

            Divider()

            // MARK: Merge / Rebase

            Button("Merge\u{2026}") {
                GroveAction.merge.post()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button("Rebase\u{2026}") {
                GroveAction.rebase.post()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            // MARK: Commit / Stash

            Button("Commit") {
                GroveAction.commit.post()
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button("Stash\u{2026}") {
                GroveAction.stash.post()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            Divider()

            // MARK: Quick Actions

            Button("Quick Actions") {
                GroveAction.quickActions.post()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        }
    }
}
