// Models/RepositoryLinkTypes.swift
// GroveKit
//
// Other working trees tied to a repository: its linked worktrees and its submodules.

import Foundation

/// One entry of `git worktree list --porcelain`.
public nonisolated struct WorktreeInfo: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    /// Checked-out branch, or nil when detached.
    public let branch: String?
    let headSHA: String
    /// The worktree that owns the `.git` directory; git always lists it first.
    public let isMain: Bool
    /// `git worktree prune` would remove it: its folder is gone.
    public let isPrunable: Bool
    public let isLocked: Bool

    public init(path: String, branch: String? = nil, headSHA: String, isMain: Bool, isPrunable: Bool, isLocked: Bool) {
        self.path = path
        self.branch = branch
        self.headSHA = headSHA
        self.isMain = isMain
        self.isPrunable = isPrunable
        self.isLocked = isLocked
    }

    public var shortSHA: String { String(headSHA.prefix(7)) }
    public var folderName: String { URL(fileURLWithPath: path).lastPathComponent }
}

/// A submodule from `.gitmodules`, with its state from `git submodule status`.
public nonisolated struct SubmoduleInfo: Identifiable, Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case upToDate
        /// Not cloned yet (`git submodule update --init` needed).
        case uninitialized
        /// Checked out at a different commit than the superproject records.
        case modified
        case conflicted
    }

    public var id: String { path }
    let name: String
    /// Path relative to the repository root.
    public let path: String
    public let url: String?
    let sha: String?
    public let state: State

    public var shortSHA: String? { sha.map { String($0.prefix(7)) } }
    public var displayName: String { URL(fileURLWithPath: path).lastPathComponent }
}
