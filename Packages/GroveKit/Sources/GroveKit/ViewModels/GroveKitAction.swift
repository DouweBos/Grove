// ViewModels/GroveKitAction.swift
// GroveKit

import Foundation

/// A git action a view model ran, for an app's telemetry. Carries no user data: no paths, names, messages or hashes.
public enum GroveKitAction: String, Sendable, CaseIterable {
    case stage
    case unstage
    case stageHunk = "stage_hunk"
    case unstageHunk = "unstage_hunk"
    case stageLines = "stage_lines"
    case unstageLines = "unstage_lines"
    case discard
    case discardHunk = "discard_hunk"
    case discardLines = "discard_lines"
    case commit
    case amend
    case checkout
    case branchCreate = "branch_create"
    case branchRename = "branch_rename"
    case branchDelete = "branch_delete"
    case merge
    case rebase
    case interactiveRebase = "interactive_rebase"
    case cherryPick = "cherry_pick"
    case revert
    case reset
    case reword
    case squash
    case drop
    case stashApply = "stash_apply"
    case stashPop = "stash_pop"
    case stashDrop = "stash_drop"
    case tagDelete = "tag_delete"
    case resolveConflict = "resolve_conflict"
    case continueOperation = "continue_operation"
    case abortOperation = "abort_operation"
    case restoreFile = "restore_file"
    /// Ignore, stop tracking, rename, move to Trash or track with LFS.
    case fileAction = "file_action"
    case applyPatch = "apply_patch"
    case setUpstream = "set_upstream"
    /// Repository config, such as the commit identity.
    case config
    case remote
    case submodule
    case worktree
    case push
    case restack
    case stackFold = "stack_fold"
    case stackRetarget = "stack_retarget"
    case gitFlow = "git_flow"
    case svn
}

/// Gets each action a view model ran and whether it succeeded; a failure's message stays on the view model.
public typealias GroveKitActionHandler = (GroveKitAction, _ succeeded: Bool) -> Void

extension HunkAction {
    var groveKitAction: GroveKitAction {
        switch self {
        case .stageHunk: .stageHunk
        case .unstageHunk: .unstageHunk
        case .discardHunk: .discardHunk
        case .stageLines: .stageLines
        case .unstageLines: .unstageLines
        case .discardLines: .discardLines
        }
    }
}
