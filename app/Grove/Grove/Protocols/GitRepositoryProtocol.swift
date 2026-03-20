// Protocols/GitRepositoryProtocol.swift
// Grove
//
// Central contract that ALL view code programs against.
// No view or ViewModel ever imports a concrete Git engine type.
// This file is owned by WS0 and frozen after Phase A.

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

// MARK: - StatusEntry

/// Working tree / index status for a single file path.
struct StatusEntry: Identifiable, Hashable, Sendable {
    /// File path relative to repository root — used as the stable identifier.
    let id: String
    let path: String
    /// Status in the index (staged area).
    let indexStatus: FileStatus
    /// Status in the working directory (unstaged).
    let workdirStatus: FileStatus
}

// MARK: - FileStatus

/// Single-character status code matching `git status --porcelain` conventions.
enum FileStatus: String, Hashable, Sendable, CaseIterable {
    case unmodified = " "
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case copied = "C"
    case untracked = "?"
    case ignored = "!"
    case conflicted = "U"
    case typeChange = "T"
}

// MARK: - DiffResult

/// Complete diff output for a single file, containing one or more hunks.
struct DiffResult: Sendable {
    let filePath: String
    /// Original path before a rename, `nil` otherwise.
    let oldPath: String?
    let isBinary: Bool
    let hunks: [HunkData]
    let stats: DiffStats
}

// MARK: - DiffStats

/// Aggregate line-change counts for a diff.
struct DiffStats: Hashable, Sendable {
    let additions: Int
    let deletions: Int
}

// MARK: - HunkData

/// One contiguous changed region inside a diff.
struct HunkData: Identifiable, Hashable, Sendable {
    /// Derived from the hunk header string; stable within a diff result.
    let id: String
    /// Raw hunk header, e.g. `@@ -10,6 +10,8 @@ func foo() {`.
    let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let lines: [DiffLine]
}

// MARK: - DiffLine

/// A single line inside a ``HunkData``.
struct DiffLine: Identifiable, Hashable, Sendable {
    let id: String
    let type: DiffLineType
    /// Raw line content, without the leading `+`/`-`/` ` prefix.
    let content: String
    /// Line number in the old file; `nil` for addition lines.
    let oldLineNumber: Int?
    /// Line number in the new file; `nil` for deletion lines.
    let newLineNumber: Int?
}

// MARK: - DiffLineType

/// Whether a diff line is context, an addition, or a deletion.
enum DiffLineType: String, Hashable, Sendable {
    case context = " "
    case addition = "+"
    case deletion = "-"
}

// MARK: - StashEntry

/// A single entry in the stash list.
struct StashEntry: Identifiable, Hashable, Sendable {
    /// Zero-based stash index (stash@{0} = 0).
    let id: Int
    let message: String
    let sha: String
    let date: Date
    /// Branch name from which the stash was created, if available.
    let branchName: String?
}

// MARK: - BlameEntry

/// One contiguous block of lines in a blame annotation sharing the same commit.
struct BlameEntry: Identifiable, Hashable, Sendable {
    let id: String
    let lineStart: Int
    let lineCount: Int
    let commitSHA: String
    let authorName: String
    let authorEmail: String
    let authorDate: Date
    let summary: String
    /// Original file path when the code was introduced (for rename tracking).
    let originalPath: String?
}

// MARK: - ReflogEntry

/// One entry from `git reflog`.
struct ReflogEntry: Identifiable, Hashable, Sendable {
    let id: String
    let oldSHA: String
    let newSHA: String
    let committerName: String
    let committerEmail: String
    let date: Date
    let message: String
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

// MARK: - FileDiff

/// Pairs a file's status entry with its optional computed diff.
struct FileDiff: Sendable {
    let path: String
    let status: FileStatus
    /// `nil` for binary files or when the diff hasn't been loaded yet.
    let diff: DiffResult?
    let stats: DiffStats
}

// MARK: - CloneProgress

/// Progress report emitted during a `git clone` operation.
struct CloneProgress: Sendable {
    let phase: ClonePhase
    let receivedObjects: Int
    let totalObjects: Int
    let receivedBytes: Int64
    /// Progress fraction in [0, 1].
    var fractionCompleted: Double {
        guard totalObjects > 0 else { return 0 }
        return Double(receivedObjects) / Double(totalObjects)
    }
}

// MARK: - ClonePhase

/// Phases of a clone operation.
enum ClonePhase: Sendable {
    case fetching
    case indexing
    case checkingOut
}

// MARK: - RepositoryState

/// Current operation state of the repository (normal or mid-operation).
enum RepositoryState: Sendable {
    case normal
    case merge
    case rebase
    case rebaseInteractive
    case revert
    case cherrypick
    case bisect
}

// MARK: - GitRepositoryProtocol

/// The central contract all view and ViewModel code depends on.
///
/// Concrete implementations include the real `GitKit.Repository` wrapper
/// and `MockGitRepository` used during development and previews.
///
/// All methods are `async throws`. Implementations must forward work to
/// a `RepositoryActor` (or equivalent) to guarantee serial access to the
/// underlying non-thread-safe libgit2 handle.
@MainActor
protocol GitRepositoryProtocol: AnyObject, Observable {
    /// Absolute URL of the repository's working directory.
    var path: URL { get }
    /// Human-readable name shown in the UI (last path component by default).
    var displayName: String { get }
    /// Currently checked-out branch, or `nil` in detached-HEAD state.
    var currentBranch: BranchInfo? { get }
    /// Whether the repository is in a special operation state (merge, rebase, …).
    var repositoryState: RepositoryState { get }

    // MARK: Status

    /// Refresh the cached status from disk.
    func refreshStatus() async throws
    /// Return current working-tree and index status entries.
    func status() async throws -> [StatusEntry]

    // MARK: Staging

    func stage(paths: [String]) async throws
    func unstage(paths: [String]) async throws
    func stageHunk(_ hunk: HunkData, in file: String) async throws
    func unstageHunk(_ hunk: HunkData, in file: String) async throws
    func stageLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws
    func unstageLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws
    func stageAll() async throws
    func unstageAll() async throws
    func discardChanges(paths: [String]) async throws
    func discardHunk(_ hunk: HunkData, in file: String) async throws

    // MARK: Diff

    /// Return the diff for one status entry. `staged: true` diffs HEAD → index;
    /// `staged: false` diffs index → working tree.
    func diff(for entry: StatusEntry, staged: Bool) async throws -> DiffResult
    /// Return all file diffs that belong to a commit.
    func diffForCommit(_ sha: String) async throws -> [FileDiff]

    // MARK: Commits

    /// Create a commit from the current index.
    @discardableResult
    func commit(message: String, body: String?, amend: Bool) async throws -> CommitInfo
    /// Return commits in reverse-chronological order.
    func log(maxCount: Int, skip: Int, branch: String?) async throws -> [CommitInfo]
    /// Return full detail for a single commit SHA.
    func commitDetail(_ sha: String) async throws -> CommitInfo

    // MARK: Branches

    func localBranches() async throws -> [BranchInfo]
    func remoteBranches() async throws -> [BranchInfo]
    @discardableResult
    func createBranch(name: String, from: String?, checkout: Bool) async throws -> BranchInfo
    func checkout(branch: String) async throws
    func deleteBranch(name: String, force: Bool) async throws
    func deleteRemoteBranch(name: String, remote: String) async throws
    func renameBranch(oldName: String, newName: String) async throws

    // MARK: Remotes

    func remotes() async throws -> [RemoteInfo]
    func fetch(remote: String?, progress: (@Sendable (Double) -> Void)?) async throws
    func pull(remote: String?, rebase: Bool, progress: (@Sendable (Double) -> Void)?) async throws
    func push(remote: String?, force: Bool, forceLease: Bool, progress: (@Sendable (Double) -> Void)?) async throws

    // MARK: Merge / Rebase

    func merge(branch: String) async throws
    func abortMerge() async throws
    func rebase(onto: String) async throws
    func abortRebase() async throws
    func continueRebase() async throws
    /// Return only conflicted files.
    func conflicts() async throws -> [StatusEntry]

    // MARK: Stash

    func stashes() async throws -> [StashEntry]
    func stashCreate(message: String?, includeUntracked: Bool) async throws
    func stashApply(index: Int, drop: Bool) async throws
    func stashDrop(index: Int) async throws

    // MARK: Tags

    func tags() async throws -> [TagInfo]
    @discardableResult
    func createTag(name: String, at sha: String?, message: String?) async throws -> TagInfo
    func deleteTag(name: String) async throws

    // MARK: Blame

    func blame(file: String, revision: String?) async throws -> [BlameEntry]

    // MARK: Reflog

    func reflog(maxCount: Int) async throws -> [ReflogEntry]
}
