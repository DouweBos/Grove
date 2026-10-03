// Domain/GitUndoManager.swift
// GroveKit
//
// Tracks git operations that can be undone/redone via Cmd+Z / Cmd+Shift+Z.

import Foundation
import Observation
import os

// MARK: - GitUndoManager

/// Maintains undo/redo stacks for reversible git operations.
///
/// Record an action immediately after it succeeds, e.g.
/// `undoManager?.record(GitUndoManager.stageAction(paths: paths, repository: repository))`.
/// The description becomes the Edit menu title ("Undo Stage README.md").
///
/// Operations that are destructive (e.g. discard changes) are **not** recorded
/// because they cannot be safely undone. Show a confirmation alert instead.
@MainActor
@Observable
public final class GitUndoManager {

    // MARK: - GitAction

    /// A single reversible git operation.
    public struct GitAction: Identifiable {
        /// Stable identity for the action within a session.
        public let id: UUID
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
    public var canUndo: Bool { !undoStack.isEmpty }
    /// Whether there is a redo action available.
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Short description of the next undo action, or `nil` when the stack is empty.
    public var undoDescription: String? { undoStack.last?.description }
    /// Short description of the next redo action, or `nil` when the stack is empty.
    public var redoDescription: String? { redoStack.last?.description }

    // MARK: - Error State

    /// Non-nil when an undo or redo operation fails, for the app to show.
    public private(set) var errorMessage: String?

    /// Called after each recorded action, e.g. so the app's Edit menu prefers git undo over stale text undo.
    @ObservationIgnored public var onActionRecorded: (() -> Void)?

    public init() {}

    // MARK: - Stack Mutation

    /// Records a newly executed action so it can be undone later.
    ///
    /// Recording a new action always clears the redo stack, matching the
    /// standard undo model (any new operation invalidates the redo history).
    public func record(_ action: GitAction) {
        undoStack.append(action)
        redoStack.removeAll()
        onActionRecorded?()
        Logger.ui.debug("GitUndoManager: recorded '\(action.description, privacy: .public)'")
    }

    // MARK: - Undo

    /// Executes the most-recently recorded undo command and pushes the action
    /// onto the redo stack.
    ///
    /// - Throws: Any error thrown by the underlying undo command.
    public func undo() async throws {
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
    public func redo() async throws {
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

    public private(set) var errorTitle = "Couldn't Undo"

    /// Records an undo/redo failure so the window can alert.
    public func reportError(_ error: Error, redo: Bool = false) {
        errorTitle = redo ? "Couldn't Redo" : "Couldn't Undo"
        errorMessage = error.localizedDescription
    }

    public func dismissError() {
        errorMessage = nil
    }

    // MARK: - Convenience Factories

    /// Undo soft-resets to the pre-commit HEAD (changes stay staged); redo re-commits
    /// the same message. Resetting to `previousHead` rather than `HEAD~1` also covers amends.
    static func commitAction(
        amend: Bool,
        previousHead: String,
        repository: any GitRepositoryProtocol,
        recommit: @escaping @MainActor () async throws -> Void
    ) -> GitAction {
        GitAction(
            description: amend ? "Amend Commit" : "Commit",
            undoCommand: { try await repository.resetToCommit(previousHead, mode: .soft) },
            redoCommand: recommit
        )
    }

    /// History rewrites (reword, drop, squash) are undone by moving HEAD back with
    /// `reset --hard`, so both directions refuse to run over uncommitted changes.
    static func rewriteAction(
        description: String,
        oldHead: String,
        newHead: String,
        repository: any GitRepositoryProtocol
    ) -> GitAction {
        let move: @MainActor (String) async throws -> Void = { target in
            guard try await isWorkingTreeClean(repository) else { throw UndoError.dirtyWorkingTree }
            try await repository.resetToCommit(target, mode: .hard)
        }
        return GitAction(
            description: description,
            undoCommand: { try await move(oldHead) },
            redoCommand: { try await move(newHead) }
        )
    }

    /// Ignores untracked files: `reset --hard` leaves them alone.
    static func isWorkingTreeClean(_ repository: any GitRepositoryProtocol) async throws -> Bool {
        try await repository.status().allSatisfy {
            $0.workdirStatus == .untracked || ($0.indexStatus == .unmodified && $0.workdirStatus == .unmodified)
        }
    }

    enum UndoError: LocalizedError {
        case dirtyWorkingTree

        var errorDescription: String? {
            "Commit or stash your uncommitted changes first; undoing this would overwrite them."
        }
    }

    /// Groups several actions into one menu entry; undo runs them in reverse order.
    static func groupedAction(description: String, actions: [GitAction]) -> GitAction {
        GitAction(
            description: description,
            undoCommand: { for action in actions.reversed() { try await action.undoCommand() } },
            redoCommand: { for action in actions { try await action.redoCommand() } }
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
    public static func deleteBranchAction(
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
    public static func checkoutAction(
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
