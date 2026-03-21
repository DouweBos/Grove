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

// MARK: - PullRequestInfo

/// A single pull request returned by the GitHub CLI.
struct PullRequestInfo: Identifiable, Hashable, Sendable {
    /// PR number used as the stable identifier.
    let id: Int
    let title: String
    /// Markdown description body, if any.
    let body: String?
    let authorName: String
    /// URL string for the author's avatar image, if available.
    let authorAvatarURL: String?
    let state: PRState
    let sourceBranch: String
    let targetBranch: String
    let createdDate: Date
    let updatedDate: Date
    let isDraft: Bool
    let labels: [PRLabel]
    let reviewers: [String]
    let checksStatus: PRChecksStatus
}

// MARK: - PRState

/// Open / closed / merged state of a pull request.
enum PRState: String, Hashable, Sendable {
    case open
    case closed
    case merged
}

// MARK: - PRLabel

/// A label attached to a pull request.
struct PRLabel: Identifiable, Hashable, Sendable {
    /// Label name used as the stable identifier.
    let id: String
    let name: String
    /// Hex colour string, e.g. `"0075ca"`.
    let color: String
}

// MARK: - PRChecksStatus

/// Aggregate status of all CI checks on a pull request.
enum PRChecksStatus: Hashable, Sendable {
    case pending
    case passing
    case failing
    case none
}

// MARK: - PRComment

/// A single comment or review on a pull request.
struct PRComment: Identifiable, Hashable, Sendable {
    let id: String
    let authorName: String
    /// URL string for the author's avatar image, if available.
    let authorAvatarURL: String?
    /// Markdown body text of the comment.
    let body: String
    let createdDate: Date
    /// True when the comment is a formal review (approve / request-changes).
    let isReview: Bool
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
    /// Return all tracked file paths in the repository via `git ls-files`.
    func listTrackedFiles() async throws -> [String]

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
    /// When `ignoreWhitespace` is `true`, whitespace-only changes are excluded.
    func diff(for entry: StatusEntry, staged: Bool, ignoreWhitespace: Bool) async throws -> DiffResult
    /// Return all file diffs that belong to a commit.
    func diffForCommit(_ sha: String) async throws -> [FileDiff]

    // MARK: Commits

    /// Create a commit from the current index.
    ///
    /// - Parameters:
    ///   - message: The commit subject line.
    ///   - body: Optional extended description appended after a blank line.
    ///   - amend: When `true`, amends the most recent commit.
    ///   - sign: When `true`, signs the commit using the configured GPG/SSH key (`-S`).
    @discardableResult
    func commit(message: String, body: String?, amend: Bool, sign: Bool) async throws -> CommitInfo

    /// Check if GPG/SSH signing is configured for this repository.
    ///
    /// Returns `true` when both `commit.gpgsign` is set to `"true"` **or**
    /// `user.signingkey` is set to a non-empty value in the effective git config.
    func isSigningConfigured() async throws -> Bool
    /// Return commits in reverse-chronological order.
    func log(maxCount: Int, skip: Int, branch: String?) async throws -> [CommitInfo]
    /// Return full detail for a single commit SHA.
    func commitDetail(_ sha: String) async throws -> CommitInfo

    /// Return commits that touched `path`, following renames (`--follow`).
    func fileLog(path: String, maxCount: Int) async throws -> [CommitInfo]

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
    /// Fetch, pull, then push in sequence — a single "sync" round-trip.
    func sync(remote: String?, rebase: Bool, progress: (@Sendable (Double) -> Void)?) async throws

    // MARK: Merge / Rebase

    func merge(branch: String) async throws
    func abortMerge() async throws
    func rebase(onto: String) async throws
    func abortRebase() async throws
    func continueRebase() async throws
    /// Return only conflicted files.
    func conflicts() async throws -> [StatusEntry]

    // MARK: Cherry-pick

    /// Apply the changes introduced by `commit` onto HEAD.
    func cherryPick(commit: String) async throws
    /// Abort an in-progress cherry-pick operation.
    func abortCherryPick() async throws

    // MARK: Revert

    /// Create a new commit that undoes the changes introduced by `commit`.
    func revert(commit: String) async throws
    /// Abort an in-progress revert operation.
    func abortRevert() async throws

    // MARK: Bisect

    /// Start a bisect session.
    func bisectStart() async throws
    /// Mark a commit (or HEAD when `commit` is `nil`) as bad.
    func bisectBad(commit: String?) async throws
    /// Mark a commit (or HEAD when `commit` is `nil`) as good.
    func bisectGood(commit: String?) async throws
    /// End the bisect session and return to the original HEAD.
    func bisectReset() async throws
    /// Return the raw lines from the current bisect log.
    func bisectLog() async throws -> [String]

    // MARK: Interactive Rebase

    /// Start an interactive rebase covering `commitCount` commits onto `onto`.
    ///
    /// Uses `GIT_SEQUENCE_EDITOR` to automate the todo-list manipulation.
    func rebaseInteractive(onto: String, commitCount: Int) async throws
    /// Squash the given `commits` into a single commit with `message`.
    func squashCommits(_ commits: [String], message: String) async throws
    /// Change the commit message of `commit` to `newMessage` via interactive rebase.
    func rewordCommit(_ commit: String, newMessage: String) async throws
    /// Remove `commit` from history via interactive rebase.
    func dropCommit(_ commit: String) async throws

    // MARK: Reset

    /// Reset HEAD (and optionally the index and working tree) to `commit`.
    func resetToCommit(_ commit: String, mode: ResetMode) async throws

    // MARK: Clean

    /// Remove untracked files (and optionally directories) from the working tree.
    ///
    /// - Parameters:
    ///   - directories: When `true`, also removes untracked directories (`-d`).
    ///   - force: Must be `true` for git to actually delete anything (`-f`).
    func cleanUntracked(directories: Bool, force: Bool) async throws

    // MARK: Stash

    func stashes() async throws -> [StashEntry]
    /// Create a new stash entry.
    ///
    /// - Parameters:
    ///   - message: Optional message for the stash entry.
    ///   - includeUntracked: When `true`, untracked files are also stashed.
    ///   - paths: When non-`nil`, only the specified file paths are stashed
    ///     (partial stash). Pass `nil` to stash all changes.
    func stashCreate(message: String?, includeUntracked: Bool, paths: [String]?) async throws
    func stashApply(index: Int, drop: Bool) async throws
    func stashDrop(index: Int) async throws

    // MARK: Tags

    func tags() async throws -> [TagInfo]
    @discardableResult
    /// Create a tag at the given commit.
    ///
    /// - Parameters:
    ///   - name: The tag name.
    ///   - sha: The commit SHA to tag, or `nil` to tag HEAD.
    ///   - message: When non-`nil`, creates an annotated tag with this message.
    ///   - sign: When `true`, signs the tag with the configured GPG/SSH key (`-s`).
    func createTag(name: String, at sha: String?, message: String?, sign: Bool) async throws -> TagInfo
    func deleteTag(name: String) async throws
    /// Push a single tag to the remote.
    func pushTag(name: String, remote: String?) async throws
    /// Push all local tags to the remote.
    func pushAllTags(remote: String?) async throws

    // MARK: Blame

    func blame(file: String, revision: String?) async throws -> [BlameEntry]

    // MARK: Reflog

    func reflog(maxCount: Int) async throws -> [ReflogEntry]

    // MARK: Pull Requests

    /// Return the list of pull requests from the GitHub CLI.
    func pullRequests() async throws -> [PullRequestInfo]
    /// Return full detail for a single pull request number.
    func pullRequestDetail(number: Int) async throws -> PullRequestInfo
    /// Return all comments and reviews for a pull request.
    func pullRequestComments(number: Int) async throws -> [PRComment]
    /// Check out the branch for a pull request via `gh pr checkout`.
    func checkoutPullRequest(number: Int) async throws
    /// Close a pull request without merging.
    func closePullRequest(number: Int) async throws
    /// Merge a pull request using the merge strategy.
    func mergePullRequest(number: Int) async throws
}

// MARK: - GitRepositoryProtocol Default Arguments

/// Convenience overloads that supply `sign: false` so existing call sites
/// that were written before signing support was added continue to compile
/// without modification.
extension GitRepositoryProtocol {

    @discardableResult
    func commit(message: String, body: String?, amend: Bool) async throws -> CommitInfo {
        try await commit(message: message, body: body, amend: amend, sign: false)
    }

    @discardableResult
    func createTag(name: String, at sha: String?, message: String?) async throws -> TagInfo {
        try await createTag(name: name, at: sha, message: message, sign: false)
    }
}
