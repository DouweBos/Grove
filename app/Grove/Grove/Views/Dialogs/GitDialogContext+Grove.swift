// Views/Dialogs/GitDialogContext+Grove.swift
// Grove
//
// What GroveUIKit's dialogs run against in Grove: the repository's own commands, undo, pins and refresh.

import Foundation
import GroveKit
import GroveUIKit

extension GitDialogContext {
    static func grove(repository: any GitRepositoryProtocol, refs: RepositoryRefs, commands: (any GitCommandPerforming)? = nil,
                      undo: GitUndoManager?, onChange: @escaping () async -> Void) -> GitDialogContext {
        var context = GitDialogContext(repository: repository, refs: refs,
                                       commands: commands ?? RepositoryCommands(repository: repository))
        context.undo = undo
        context.onChange = onChange
        context.pinBranch = { BranchPins.pin($0, inRepositoryAt: repository.path.path) }
        return context
    }
}

extension SidebarViewModel {
    /// Adds what only the sidebar knows: fetching an added remote and the worktrees a branch is checked out in.
    var dialogContext: GitDialogContext {
        var context = GitDialogContext.grove(repository: repository, refs: refs, commands: actions.commands, undo: undoManager) {
            [weak self] in await self?.didChangeRepository()
        }
        let actions = actions
        context.onRemoteAdded = { name in Task { await actions.fetchAddedRemote(name) } }
        context.worktrees = GitDialogWorktrees(
            checkingOut: { actions.worktree(checkingOut: $0) },
            remove: { worktree, force, branch, forceBranch in
                try await actions.removeWorktree(worktree, force: force, deleting: branch, forceBranch: forceBranch)
            },
            open: { [weak self] in self?.openInNewTab($0) })
        return context
    }
}
