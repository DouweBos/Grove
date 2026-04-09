// GitKit/GitRepositoryProtocol.swift
// Grove
//
// Central contract that ALL view code programs against.
// No view or ViewModel ever imports a concrete Git engine type.

import Foundation

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
    func discardLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws

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
    /// Returns `true` when either `commit.gpgsign` is set to `"true"` **or**
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
    func push(remote: String?, force: Bool, forceWithLease: Bool, progress: (@Sendable (Double) -> Void)?) async throws
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
    /// Create a tag at the given commit.
    ///
    /// - Parameters:
    ///   - name: The tag name.
    ///   - sha: The commit SHA to tag, or `nil` to tag HEAD.
    ///   - message: When non-`nil`, creates an annotated tag with this message.
    ///   - sign: When `true`, signs the tag with the configured GPG/SSH key (`-s`).
    @discardableResult
    func createTag(name: String, at sha: String?, message: String?, sign: Bool) async throws -> TagInfo
    func deleteTag(name: String) async throws
    /// Push a single tag to the remote.
    func pushTag(name: String, remote: String?) async throws
    /// Push all local tags to the remote.
    func pushAllTags(remote: String?) async throws

    // MARK: Submodules

    /// Update a submodule at the given path (`git submodule update --init <path>`).
    func updateSubmodule(path: String) async throws

    // MARK: Worktrees

    /// Remove a linked worktree (`git worktree remove <path>`).
    func removeWorktree(path: String, force: Bool) async throws

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
