// Models/GitTypes.swift
// GroveKit
//
// Core Git domain types used across the app.

import Foundation

// MARK: - CommitInfo

/// A snapshot of a single Git commit.
public struct CommitInfo: Identifiable, Hashable, Sendable {
    /// Full 40-character SHA.
    public let id: String
    /// Abbreviated 7-character SHA.
    public var shortSHA: String { String(id.prefix(7)) }
    /// Full commit message (subject + blank line + body).
    public let message: String
    /// First line of the commit message.
    public let summary: String
    /// Body of the commit message (everything after the first blank line), if any.
    public let body: String?
    public let authorName: String
    public let authorEmail: String
    public let authorDate: Date
    public let committerName: String
    public let committerEmail: String
    public let committerDate: Date
    /// SHA strings of parent commits.
    public let parentIDs: [String]
    /// True when the commit has more than one parent.
    public var isMerge: Bool { parentIDs.count > 1 }
    /// True when the commit carries a GPG/SSH signature.
    public let isSigned: Bool

    public init(id: String, message: String, summary: String, body: String? = nil, authorName: String, authorEmail: String, authorDate: Date, committerName: String, committerEmail: String, committerDate: Date, parentIDs: [String], isSigned: Bool) {
        self.id = id
        self.message = message
        self.summary = summary
        self.body = body
        self.authorName = authorName
        self.authorEmail = authorEmail
        self.authorDate = authorDate
        self.committerName = committerName
        self.committerEmail = committerEmail
        self.committerDate = committerDate
        self.parentIDs = parentIDs
        self.isSigned = isSigned
    }
}

// MARK: - BranchInfo

/// Describes a local or remote branch reference.
public struct BranchInfo: Identifiable, Hashable, Sendable {
    /// Full ref name, e.g. `refs/heads/main` or `refs/remotes/origin/main`.
    public let id: String
    /// Short human-readable name, e.g. `main`.
    public let name: String
    public let isLocal: Bool
    public let isRemote: Bool
    /// True when this branch is currently checked out (HEAD).
    public let isHEAD: Bool
    /// SHA the branch ref points at.
    public let targetSHA: String
    /// Remote name for remote-tracking branches (e.g. `origin`).
    public let remoteName: String?
    /// Name of the configured upstream tracking branch, if any.
    public let upstream: String?
    /// Commits the local branch is ahead of its upstream.
    public let ahead: Int
    /// Commits the local branch is behind its upstream.
    public let behind: Int

    public init(id: String, name: String, isLocal: Bool, isRemote: Bool, isHEAD: Bool, targetSHA: String, remoteName: String? = nil, upstream: String? = nil, ahead: Int, behind: Int) {
        self.id = id
        self.name = name
        self.isLocal = isLocal
        self.isRemote = isRemote
        self.isHEAD = isHEAD
        self.targetSHA = targetSHA
        self.remoteName = remoteName
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
    }
}

// MARK: - TagInfo

/// Describes a lightweight or annotated tag.
public struct TagInfo: Identifiable, Hashable, Sendable {
    /// Tag name used as the stable identifier.
    public let id: String
    public let name: String
    /// SHA of the tagged object (commit or tag object).
    public let targetSHA: String
    public let isAnnotated: Bool
    /// Tag message for annotated tags.
    let message: String?
    let taggerName: String?
    let taggerDate: Date?
}

// MARK: - RemoteInfo

/// Describes a configured Git remote.
public struct RemoteInfo: Identifiable, Hashable, Sendable {
    /// Remote name used as the stable identifier (e.g. `origin`).
    public let id: String
    public let name: String
    public let url: String
    /// Separate push URL, if configured.
    let pushURL: String?

    public init(id: String, name: String, url: String, pushURL: String? = nil) {
        self.id = id
        self.name = name
        self.url = url
        self.pushURL = pushURL
    }
}

// MARK: - RepositoryState

/// Current operation state of the repository (normal or mid-operation).
public enum RepositoryState: Sendable, Equatable {
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
public enum ResetMode: String, Sendable {
    /// Move HEAD only; leave index and working tree untouched.
    case soft
    /// Move HEAD and reset the index; leave working tree untouched.
    case mixed
    /// Move HEAD, reset index, and discard all working-tree changes.
    case hard
}

// MARK: - PullStrategy

/// How `git pull` integrates fetched commits; always passed explicitly so `pull.rebase` / `pull.ff` can't override the choice.
public enum PullStrategy: String, CaseIterable, Sendable {
    case merge
    case rebase
    case fastForwardOnly

    public var title: String {
        switch self {
        case .merge: "Merge"
        case .rebase: "Rebase"
        case .fastForwardOnly: "Fast-Forward"
        }
    }

    public var summary: String {
        switch self {
        case .merge: "Creates a merge commit when your branch and the remote have diverged."
        case .rebase: "Replays your local commits on top of the fetched ones."
        case .fastForwardOnly: "Only moves your branch forward; fails if it has diverged."
        }
    }
}

/// Extra `git pull` flags; git only forwards them to merge, so a rebase ignores both.
public struct PullOptions: Sendable, Equatable {
    /// `--verify-signatures`: refuse unless the fetched tip carries a valid signature.
    public var verifySignatures = false
    /// `--no-verify`: skip the pre-merge-commit and commit-msg hooks.
    public var skipHooks = false

    public init(verifySignatures: Bool = false, skipHooks: Bool = false) {
        self.verifySignatures = verifySignatures
        self.skipHooks = skipHooks
    }
}

/// Extra `git push` flags.
public struct PushOptions: Sendable, Equatable {
    /// `--recurse-submodules=<mode>`; nil leaves `push.recurseSubmodules` in charge.
    public var recurseSubmodules: SubmodulePushMode?
    /// `--no-verify`: skip the pre-push hook.
    public var skipHooks = false

    public init(recurseSubmodules: SubmodulePushMode? = nil, skipHooks: Bool = false) {
        self.recurseSubmodules = recurseSubmodules
        self.skipHooks = skipHooks
    }
}

public enum SubmodulePushMode: String, CaseIterable, Sendable {
    /// Refuse the push when a referenced submodule commit isn't on its remote.
    case check
    /// Push submodules that need it before the superproject.
    case onDemand = "on-demand"

    public var title: String {
        switch self {
        case .check: "Verify submodules before push"
        case .onDemand: "Push submodules first"
        }
    }
}

// MARK: - BranchComparison

/// Both sides of `git log --left-right --cherry-mark base...compare`, plus the files `compare` changed since the merge base.
public struct BranchComparison: Sendable {
    public var onlyInBase: [CommitInfo] = []
    public var onlyInCompare: [CommitInfo] = []
    /// Commits whose patch exists on both sides (cherry-picked or rebased), counted once per pair.
    public var equivalentCount = 0
    public var files: [ChangedFileStat] = []

    public init(onlyInBase: [CommitInfo] = [], onlyInCompare: [CommitInfo] = [], equivalentCount: Int = 0, files: [ChangedFileStat] = []) {
        self.onlyInBase = onlyInBase
        self.onlyInCompare = onlyInCompare
        self.equivalentCount = equivalentCount
        self.files = files
    }
}

/// A local branch tip from one `git for-each-ref refs/heads` pass.
public struct BranchTip: Hashable, Sendable {
    public let name: String
    let sha: String
    let committerDate: Date?
    let authorName: String
    let summary: String
}

/// Commits a branch has that its base lacks (ahead) and vice versa (behind).
public struct AheadBehind: Hashable, Sendable {
    let ahead: Int
    let behind: Int
}

/// One `git diff --numstat` row; counts are nil for binary files.
public struct ChangedFileStat: Identifiable, Hashable, Sendable {
    public var id: String { path }
    public let path: String
    public let additions: Int?
    public let deletions: Int?

    public init(path: String, additions: Int? = nil, deletions: Int? = nil) {
        self.path = path
        self.additions = additions
        self.deletions = deletions
    }
}

extension BranchInfo {
    /// "origin/main" rather than "refs/remotes/origin/main".
    public var upstreamShortName: String? {
        upstream.map { $0.hasPrefix("refs/remotes/") ? String($0.dropFirst("refs/remotes/".count)) : $0 }
    }

    public var upstreamRemoteName: String? {
        upstreamShortName?.split(separator: "/").first.map(String.init)
    }
}
