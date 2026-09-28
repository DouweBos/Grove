// Commands/GroveCommands.swift
// Grove
//
// SwiftUI Commands structs that register Grove's full menu-bar keyboard
// shortcut surface.
//
// Commands cannot directly access RepositoryViewModel because they live
// outside the SwiftUI environment hierarchy. Instead every action is
// dispatched through GroveAction.post(), which posts a Notification that
// RootWindowHost observes and forwards to the active RepositorySession.
//
// The one exception is the Undo/Redo group, which reads git and text undo
// state through EditUndoState to title and enable its items.

import SwiftUI

// MARK: - GroveCommands

/// Aggregates all Grove menu-bar command groups into a single Commands value.
///
/// Add to a `Scene` via `.commands { GroveCommands() }`.
struct GroveCommands: Commands {

    // MARK: Body

    var body: some Commands {
        GroveFileCommands()
        GroveUndoRedoCommands()
        GroveNavigateCommands()
        GroveGitCommands()
    }
}

// MARK: - GroveFileCommands

/// Replaces File > New with the ways to get a repository into Grove.
private struct GroveFileCommands: Commands {

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Repository\u{2026}") { GroveAction.createRepository.post() }
                .keyboardShortcut("n", modifiers: .command)
            Button("Add Existing Repository\u{2026}") { GroveAction.addRepository.post() }
                .keyboardShortcut("o", modifiers: .command)
            Button("Clone Repository\u{2026}") { GroveAction.cloneRepository.post() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("New Group\u{2026}") { GroveAction.newGroup.post() }
            Divider()
            Button("Local Repositories") { GroveAction.showLocalRepositories.post() }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Button("Remote Repositories") { GroveAction.showRemoteRepositories.post() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }
}

// MARK: - GroveUndoRedoCommands

/// Replaces Edit > Undo/Redo: text editing keeps the system behaviour, otherwise
/// the focused repository's git stack is used ("Undo Commit 'fix: login'").
private struct GroveUndoRedoCommands: Commands {

    private let edit = EditUndoState.shared

    /// A text field with its own history wins; the Preferences window has no git stack.
    private var gitUndoTarget: GitUndoManager? {
        edit.isEditingText && edit.canUndo ? nil : edit.gitUndo.flatMap { $0.canUndo ? $0 : nil }
    }

    private var gitRedoTarget: GitUndoManager? {
        edit.isEditingText && edit.canRedo ? nil : edit.gitUndo.flatMap { $0.canRedo ? $0 : nil }
    }

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            Button(gitUndoTarget?.undoDescription.map { "Undo \($0)" } ?? edit.undoTitle) {
                edit.refresh()
                if gitUndoTarget != nil { GroveAction.undo.post() } else { edit.forward(undo: true) }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(gitUndoTarget == nil && !edit.canUndo)

            Button(gitRedoTarget?.redoDescription.map { "Redo \($0)" } ?? edit.redoTitle) {
                edit.refresh()
                if gitRedoTarget != nil { GroveAction.redo.post() } else { edit.forward(undo: false) }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(gitRedoTarget == nil && !edit.canRedo)
        }
    }
}

// MARK: - GroveNavigateCommands

/// Adds a **Navigate** menu with shortcuts to switch the active sidebar item.
private struct GroveNavigateCommands: Commands {

    var body: some Commands {
        CommandMenu("Navigate") {
            Button("Back") { GroveAction.navigateBack.post() }
                .keyboardShortcut("[", modifiers: .command)
            Button("Forward") { GroveAction.navigateForward.post() }
                .keyboardShortcut("]", modifiers: .command)
            Divider()

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

            Button("Blame") {
                GroveAction.navigateBlame.post()
            }
            .keyboardShortcut("7", modifiers: .command)

            Button("Repository Settings") {
                GroveAction.navigateSettings.post()
            }
            .keyboardShortcut("8", modifiers: .command)
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
