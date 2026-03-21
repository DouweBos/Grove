// Domain/GitUndoManager.swift
// Grove
//
// Tracks git operations that can be undone/redone via Cmd+Z / Cmd+Shift+Z.
// Dispatches through GroveAction so the menu bar and window view stay decoupled.

import Foundation
import Observation
import os

// MARK: - GitUndoManager

/// Maintains undo/redo stacks for reversible git operations.
///
/// Record an action immediately after executing it:
/// ```swift
/// try await repository.commit(message: msg, body: nil, amend: false)
/// undoManager.record(GitUndoManager.GitAction(
///     description: "Commit '\(msg)'",
///     undoCommand: { try await repository.resetToCommit("HEAD~1", mode: .soft) },
///     redoCommand: { try await repository.commit(message: msg, body: nil, amend: false) }
/// ))
/// ```
///
/// Operations that are destructive (e.g. discard changes) are **not** recorded
/// because they cannot be safely undone. Show a confirmation alert instead.
@MainActor
@Observable
final class GitUndoManager {

    // MARK: - GitAction

    /// A single reversible git operation.
    struct GitAction: Identifiable {
        /// Stable identity for the action within a session.
        let id: UUID
        /// Human-readable description shown in the Edit menu (e.g. "Commit 'fix: login bug'").
        let description: String
        /// Async closure that reverts the operation.
        let undoCommand: @MainActor () async throws -> Void
        /// Async closure that re-applies the operation after an undo.
        let redoCommand: @MainActor () async throws -> Void

        init(
            id: UUID = UUID(),
            description: String,
            undoCommand: @escaping @MainActor () async throws -> Void,
            redoCommand: @escaping @MainActor () async throws -> Void
        ) {
            self.id = id
            self.description = description
            self.undoCommand = undoCommand
            self.redoCommand = redoCommand
        }
    }

    // MARK: - Observable State

    /// Actions that can be undone, most-recent last.
    private(set) var undoStack: [GitAction] = []
    /// Actions that can be redone after an undo, most-recent last.
    private(set) var redoStack: [GitAction] = []

    /// Whether there is an undo action available.
    var canUndo: Bool { !undoStack.isEmpty }
    /// Whether there is a redo action available.
    var canRedo: Bool { !redoStack.isEmpty }

    /// Short description of the next undo action, or `nil` when the stack is empty.
    var undoDescription: String? { undoStack.last?.description }
    /// Short description of the next redo action, or `nil` when the stack is empty.
    var redoDescription: String? { redoStack.last?.description }

    // MARK: - Error State

    /// Non-nil when an undo or redo operation fails.
    var errorMessage: String?

    // MARK: - Stack Mutation

    /// Records a newly executed action so it can be undone later.
    ///
    /// Recording a new action always clears the redo stack, matching the
    /// standard undo model (any new operation invalidates the redo history).
    func record(_ action: GitAction) {
        undoStack.append(action)
        redoStack.removeAll()
        Logger.ui.debug("GitUndoManager: recorded '\(action.description, privacy: .public)'")
    }

    // MARK: - Undo

    /// Executes the most-recently recorded undo command and pushes the action
    /// onto the redo stack.
    ///
    /// - Throws: Any error thrown by the underlying undo command.
    func undo() async throws {
        guard let action = undoStack.last else { return }
        undoStack.removeLast()
        do {
            Logger.ui.info("GitUndoManager: undoing '\(action.description, privacy: .public)'")
            try await action.undoCommand()
            redoStack.append(action)
        } catch {
            // Re-add to the undo stack on failure so state stays consistent.
            undoStack.append(action)
            Logger.ui.error("GitUndoManager: undo failed for '\(action.description, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - Redo

    /// Re-applies the most-recently undone command and pushes it back onto
    /// the undo stack.
    ///
    /// - Throws: Any error thrown by the underlying redo command.
    func redo() async throws {
        guard let action = redoStack.last else { return }
        redoStack.removeLast()
        do {
            Logger.ui.info("GitUndoManager: redoing '\(action.description, privacy: .public)'")
            try await action.redoCommand()
            undoStack.append(action)
        } catch {
            // Re-add to the redo stack on failure so state stays consistent.
            redoStack.append(action)
            Logger.ui.error("GitUndoManager: redo failed for '\(action.description, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    // MARK: - Convenience Factories

    /// Returns a pre-built ``GitAction`` for undoing a commit via `git reset --soft HEAD~1`.
    ///
    /// - Parameters:
    ///   - commitSummary: The first line of the commit message, shown in the menu.
    ///   - repository: The repository to operate on.
    static func commitAction(
        commitSummary: String,
        repository: any GitRepositoryProtocol
    ) -> GitAction {
        GitAction(
            description: "Commit '\(commitSummary)'",
            undoCommand: {
                try await repository.resetToCommit("HEAD~1", mode: .soft)
            },
            redoCommand: {
                // Redo re-commits with the same message; callers may prefer to
                // handle this themselves and pass a custom closure.
                _ = try await repository.commit(message: commitSummary, body: nil, amend: false)
            }
        )
    }

    /// Returns a pre-built ``GitAction`` for undoing a stage operation.
    static func stageAction(
        paths: [String],
        repository: any GitRepositoryProtocol
    ) -> GitAction {
        GitAction(
            description: "Stage \(paths.count == 1 ? paths[0] : "\(paths.count) files")",
            undoCommand: {
                try await repository.unstage(paths: paths)
            },
            redoCommand: {
                try await repository.stage(paths: paths)
            }
        )
    }

    /// Returns a pre-built ``GitAction`` for undoing an unstage operation.
    static func unstageAction(
        paths: [String],
        repository: any GitRepositoryProtocol
    ) -> GitAction {
        GitAction(
            description: "Unstage \(paths.count == 1 ? paths[0] : "\(paths.count) files")",
            undoCommand: {
                try await repository.stage(paths: paths)
            },
            redoCommand: {
                try await repository.unstage(paths: paths)
            }
        )
    }

    /// Returns a pre-built ``GitAction`` for undoing branch creation.
    static func createBranchAction(
        branchName: String,
        repository: any GitRepositoryProtocol
    ) -> GitAction {
        GitAction(
            description: "Create Branch '\(branchName)'",
            undoCommand: {
                try await repository.deleteBranch(name: branchName, force: false)
            },
            redoCommand: {
                _ = try await repository.createBranch(name: branchName, from: nil, checkout: false)
            }
        )
    }

    /// Returns a pre-built ``GitAction`` for undoing branch deletion.
    ///
    /// - Parameters:
    ///   - branchName: The name of the deleted branch.
    ///   - sha: The SHA the branch pointed at before deletion (must be captured before calling `deleteBranch`).
    ///   - repository: The repository to operate on.
    static func deleteBranchAction(
        branchName: String,
        sha: String,
        repository: any GitRepositoryProtocol
    ) -> GitAction {
        GitAction(
            description: "Delete Branch '\(branchName)'",
            undoCommand: {
                // Restore the branch at its original commit.
                _ = try await repository.createBranch(name: branchName, from: sha, checkout: false)
            },
            redoCommand: {
                try await repository.deleteBranch(name: branchName, force: true)
            }
        )
    }

    /// Returns a pre-built ``GitAction`` for undoing a checkout.
    ///
    /// - Parameters:
    ///   - targetBranch: The branch being checked out.
    ///   - previousBranch: The branch that was checked out before the switch.
    ///   - repository: The repository to operate on.
    static func checkoutAction(
        targetBranch: String,
        previousBranch: String,
        repository: any GitRepositoryProtocol
    ) -> GitAction {
        GitAction(
            description: "Checkout '\(targetBranch)'",
            undoCommand: {
                try await repository.checkout(branch: previousBranch)
            },
            redoCommand: {
                try await repository.checkout(branch: targetBranch)
            }
        )
    }
}
