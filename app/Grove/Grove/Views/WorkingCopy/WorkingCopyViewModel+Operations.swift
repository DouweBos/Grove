// Views/WorkingCopy/WorkingCopyViewModel+Operations.swift
// Grove
//
// Conflict resolution and continuing or aborting a merge, rebase, cherry-pick or revert.

import Foundation

extension WorkingCopyViewModel {

    /// Jump to the first unresolved file so the diff panel shows the resolution UI.
    func resolveNextConflict() async {
        guard let first = conflictedFiles.first else { return }
        await select(first)
    }

    func resolveConflict(taking side: ConflictSide) async {
        guard let entry = selectedEntry, entry.isConflicted else { return }
        await mutate { try await self.repository.resolveConflict(path: entry.path, side: side) }
        if let next = conflictedFiles.first { await select(next) }
    }

    func abortOperation() async {
        await runOperation {
            let repo = self.repository
            switch self.repositoryState {
            case .rebase, .rebaseInteractive: try await repo.abortRebase()
            case .cherrypick: try await repo.abortCherryPick()
            case .revert: try await repo.abortRevert()
            default: try await repo.abortMerge()
            }
        }
    }

    func continueOperation() async {
        await runOperation { try await self.repository.continueOperation() }
    }

    private func runOperation(_ work: @escaping () async throws -> Void) async {
        isRunningOperation = true
        defer { isRunningOperation = false }
        await mutate(work)
    }
}
