// Models/RepositoryLinkTypes.swift
// GroveKit
//
// Other working trees tied to a repository: its linked worktrees and its submodules.

import Foundation

/// One entry of `git worktree list --porcelain`.
nonisolated struct WorktreeInfo: Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    /// Checked-out branch, or nil when detached.
    let branch: String?
    let headSHA: String
    /// The worktree that owns the `.git` directory; git always lists it first.
    let isMain: Bool
    /// `git worktree prune` would remove it: its folder is gone.
    let isPrunable: Bool
    let isLocked: Bool

    var shortSHA: String { String(headSHA.prefix(7)) }
    var folderName: String { URL(fileURLWithPath: path).lastPathComponent }
}

/// A submodule from `.gitmodules`, with its state from `git submodule status`.
nonisolated struct SubmoduleInfo: Identifiable, Hashable, Sendable {
    enum State: Hashable, Sendable {
        case upToDate
        /// Not cloned yet (`git submodule update --init` needed).
        case uninitialized
        /// Checked out at a different commit than the superproject records.
        case modified
        case conflicted
    }

    var id: String { path }
    let name: String
    /// Path relative to the repository root.
    let path: String
    let url: String?
    let sha: String?
    let state: State

    var shortSHA: String? { sha.map { String($0.prefix(7)) } }
    var displayName: String { URL(fileURLWithPath: path).lastPathComponent }
}
