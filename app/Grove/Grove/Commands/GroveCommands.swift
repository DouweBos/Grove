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
//
// The one exception is the Undo/Redo group, which reads undo state through
// a FocusedValue so menu items can be correctly titled and enabled.

import SwiftUI

// MARK: - FocusedValues: GitUndoManager

/// FocusedValues extension exposing the active window's ``GitUndoManager``
/// to Commands structs.
struct GitUndoManagerKey: FocusedValueKey {
    typealias Value = GitUndoManager
}

extension FocusedValues {
    /// The ``GitUndoManager`` of the currently focused repository window.
    var gitUndoManager: GitUndoManager? {
        get { self[GitUndoManagerKey.self] }
        set { self[GitUndoManagerKey.self] = newValue }
    }
}

// MARK: - GroveCommands

/// Aggregates all Grove menu-bar command groups into a single Commands value.
///
/// Add to a `Scene` via `.commands { GroveCommands() }`.
struct GroveCommands: Commands {

    // MARK: Body

    var body: some Commands {
        GroveUndoRedoCommands()
        GroveTabCommands()
        GroveNavigateCommands()
        GroveGitCommands()
    }
}

// MARK: - GroveUndoRedoCommands

/// Replaces the system Undo/Redo items in the **Edit** menu with Grove-aware
/// versions that show the current git operation description.
///
/// Reads undo state from the focused window via ``FocusedValues/gitUndoManager``.
private struct GroveUndoRedoCommands: Commands {

    @FocusedValue(\.gitUndoManager) private var undoManager: GitUndoManager?

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button("Undo \(undoManager?.undoDescription ?? "")") {
                GroveAction.undo.post()
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!(undoManager?.canUndo ?? false))

            Button("Redo \(undoManager?.redoDescription ?? "")") {
                GroveAction.redo.post()
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!(undoManager?.canRedo ?? false))
        }
    }
}

// MARK: - GroveTabCommands

/// Adds tab management items to the **File** menu.
///
/// Cmd+T / Cmd+W are handled here so they work from the menu bar and are
/// visible in the keyboard shortcut system. The actual tab mutations are
/// performed by ``RepositoryWindowHost`` via ``GroveTabAction``.
private struct GroveTabCommands: Commands {

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Tab") {
                GroveTabAction.newTab.post()
            }
            .keyboardShortcut("t", modifiers: .command)

            Button("Close Tab") {
                GroveTabAction.closeTab.post()
            }
            .keyboardShortcut("w", modifiers: .command)

            Divider()

            Button("Select Next Tab") {
                GroveTabAction.nextTab.post()
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])

            Button("Select Previous Tab") {
                GroveTabAction.previousTab.post()
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
        }
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

            Button("Reflog") {
                GroveAction.navigateReflog.post()
            }
            .keyboardShortcut("4", modifiers: .command)

            Button("Pull Requests") {
                GroveAction.navigatePullRequests.post()
            }
            .keyboardShortcut("5", modifiers: .command)

            Button("Branches Review") {
                GroveAction.navigateBranchesReview.post()
            }
            .keyboardShortcut("6", modifiers: .command)
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

            Button("Quick Open\u{2026}") {
                GroveAction.quickOpen.post()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
        }
    }
}
