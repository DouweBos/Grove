// ViewModels/WorkingCopyViewModel+Operations.swift
// GroveKit
//
// Conflict resolution and continuing or aborting a merge, rebase, cherry-pick or revert.

import Foundation

extension WorkingCopyViewModel {

    /// Jump to the first unresolved file so the diff panel shows the resolution UI.
    public func resolveNextConflict() async {
        guard let first = conflictedFiles.first else { return }
        await select(first)
    }

    public func resolveConflict(taking side: ConflictSide) async {
        guard let entry = selectedEntry, entry.isConflicted else { return }
        await mutate(.resolveConflict) { try await self.repository.resolveConflict(path: entry.path, side: side) }
        if let next = conflictedFiles.first { await select(next) }
    }

    public func abortOperation() async {
        await runOperation(.abortOperation) {
            let repo = self.repository
            if self.pendingRestack != nil { return try await repo.abortRestack() }
            switch self.repositoryState {
            case .rebase, .rebaseInteractive: try await repo.abortRebase()
            case .cherrypick: try await repo.abortCherryPick()
            case .revert: try await repo.abortRevert()
            default: try await repo.abortMerge()
            }
        }
    }

    public func continueOperation() async {
        await runOperation(.continueOperation) {
            guard self.pendingRestack != nil else { return try await self.repository.continueOperation() }
            do {
                try await self.repository.continueRestack()
            } catch RestackError.stopped {
                // The next layer conflicted too; the banner already says where the cascade is.
            }
        }
    }

    private func runOperation(_ action: GroveKitAction, _ work: @escaping () async throws -> Void) async {
        isRunningOperation = true
        defer { isRunningOperation = false }
        await mutate(action, work)
    }
}
