// Models/GitTypes.swift
// Grove
//
// Core Git domain types used across the app.

import Foundation

// MARK: - CommitInfo

/// A snapshot of a single Git commit.
struct CommitInfo: Identifiable, Hashable, Sendable {
    /// Full 40-character SHA.
    let id: String
    /// Abbreviated 7-character SHA.
    var shortSHA: String { String(id.prefix(7)) }
    /// Full commit message (subject + blank line + body).
    let message: String
    /// First line of the commit message.
    let summary: String
    /// Body of the commit message (everything after the first blank line), if any.
    let body: String?
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let committerName: String
    let committerEmail: String
    let committerDate: Date
    /// SHA strings of parent commits.
    let parentIDs: [String]
    /// True when the commit has more than one parent.
    var isMerge: Bool { parentIDs.count > 1 }
    /// True when the commit carries a GPG/SSH signature.
    let isSigned: Bool
}

// MARK: - BranchInfo

/// Describes a local or remote branch reference.
struct BranchInfo: Identifiable, Hashable, Sendable {
    /// Full ref name, e.g. `refs/heads/main` or `refs/remotes/origin/main`.
    let id: String
    /// Short human-readable name, e.g. `main`.
    let name: String
    let isLocal: Bool
    let isRemote: Bool
    /// True when this branch is currently checked out (HEAD).
    let isHEAD: Bool
    /// SHA the branch ref points at.
    let targetSHA: String
    /// Remote name for remote-tracking branches (e.g. `origin`).
    let remoteName: String?
    /// Name of the configured upstream tracking branch, if any.
    let upstream: String?
    /// Commits the local branch is ahead of its upstream.
    let ahead: Int
    /// Commits the local branch is behind its upstream.
    let behind: Int
}

// MARK: - TagInfo

/// Describes a lightweight or annotated tag.
struct TagInfo: Identifiable, Hashable, Sendable {
    /// Tag name used as the stable identifier.
    let id: String
    let name: String
    /// SHA of the tagged object (commit or tag object).
    let targetSHA: String
    let isAnnotated: Bool
    /// Tag message for annotated tags.
    let message: String?
    let taggerName: String?
    let taggerDate: Date?
}

// MARK: - RemoteInfo

/// Describes a configured Git remote.
struct RemoteInfo: Identifiable, Hashable, Sendable {
    /// Remote name used as the stable identifier (e.g. `origin`).
    let id: String
    let name: String
    let url: String
    /// Separate push URL, if configured.
    let pushURL: String?
}

// MARK: - RepositoryState

/// Current operation state of the repository (normal or mid-operation).
enum RepositoryState: Sendable, Equatable {
    case normal
    case merge
    case rebase
    case rebaseInteractive
    case revert
    case cherrypick
    case bisect
}

// MARK: - ResetMode

/// The three reset modes accepted by `git reset`.
enum ResetMode: String, Sendable {
    /// Move HEAD only; leave index and working tree untouched.
    case soft
    /// Move HEAD and reset the index; leave working tree untouched.
    case mixed
    /// Move HEAD, reset index, and discard all working-tree changes.
    case hard
}
