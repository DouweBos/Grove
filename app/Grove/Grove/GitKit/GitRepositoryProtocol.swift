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
protocol GitRepositoryProtocol: AnyObject, Observable, StackGitOperations, CIRepositoryProtocol {
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
    /// The commit's diff limited to one path; renames into that path show as additions.
    func diffForCommit(_ sha: String, path: String) async throws -> [FileDiff]
    /// Every file path in the commit's tree (`git ls-tree -r`).
    func filesInCommit(_ sha: String) async throws -> [String]

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
    /// Commits reachable from any of `revisions` (HEAD when empty), newest first.
    func log(maxCount: Int, skip: Int, revisions: [String]) async throws -> [CommitInfo]
    /// SHAs reachable from `revision` but not from `base`.
    func commits(in revision: String, notIn base: String) async throws -> Set<String>
    /// `git format-patch` of each of `commits` (oldest first), as one mbox.
    func formatPatch(commits: [String]) async throws -> String
    /// `git archive` of `revision`'s tree to `url`, zip or tar by its extension.
    func archive(revision: String, to url: URL) async throws
    /// Whether `commit` is `descendant` or one of its ancestors.
    func isAncestor(_ commit: String, of descendant: String) async -> Bool
    /// Return full detail for a single commit SHA.
    func commitDetail(_ sha: String) async throws -> CommitInfo

    /// Return commits that touched `path`, following renames (`--follow`).
    func fileLog(path: String, maxCount: Int) async throws -> [CommitInfo]

    // MARK: Branches

    func localBranches() async throws -> [BranchInfo]
    func remoteBranches() async throws -> [BranchInfo]
    @discardableResult
    func createBranch(name: String, from: String?, checkout: Bool) async throws -> BranchInfo
    /// `track` makes the new branch push to and pull from `from`; `parent` is recorded in the repository's config.
    @discardableResult
    func createBranch(name: String, from: String?, checkout: Bool, track: Bool, parent: String?) async throws -> BranchInfo
    /// Parent branch recorded at creation, keyed by branch name.
    func branchParents() async throws -> [String: String]
    func checkout(branch: String) async throws
    func deleteBranch(name: String, force: Bool) async throws
    func deleteRemoteBranch(name: String, remote: String) async throws
    func renameBranch(oldName: String, newName: String) async throws
    /// Makes `branch` track `remoteBranch` (e.g. `origin/main`); nil stops it tracking anything.
    func setUpstream(of branch: String, to remoteBranch: String?) async throws

    // MARK: Remotes

    func remotes() async throws -> [RemoteInfo]
    func fetch(remote: String?, progress: (@Sendable (Double) -> Void)?) async throws
    func pull(remote: String?, strategy: PullStrategy, progress: (@Sendable (Double) -> Void)?) async throws
    /// Pulls `branch` from `remote` into the checked-out branch (the upstream when both are nil);
    /// with `.rebase` that rebases it onto that branch.
    func pull(remote: String?, branch: String?, strategy: PullStrategy, options: PullOptions,
              progress: (@Sendable (Double) -> Void)?) async throws
    /// Pushes HEAD; `setUpstream` adds `-u` so a branch's first push starts tracking the remote branch.
    func push(remote: String?, forceWithLease: Bool, setUpstream: Bool, progress: (@Sendable (Double) -> Void)?) async throws
    /// Pushes HEAD to `branch` on `remote`, which may differ from the local branch's name.
    func push(remote: String, branch: String, forceWithLease: Bool, setUpstream: Bool, options: PushOptions,
              progress: (@Sendable (Double) -> Void)?) async throws
    /// Fetch, pull, then push in sequence; a branch without an upstream is pushed with `-u`.
    func sync(remote: String?, strategy: PullStrategy, progress: (@Sendable (Double) -> Void)?) async throws
    /// The strategy the effective `pull.rebase` / `pull.ff` config implies.
    func defaultPullStrategy() async -> PullStrategy

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

    /// Replays `steps` (oldest first) onto `base` as an interactive rebase driven by `GIT_SEQUENCE_EDITOR`.
    func rebaseInteractive(onto base: String, steps: [RebaseStep]) async throws
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
    /// Stores the working state as a stash but leaves the working copy as it is; false when there was nothing to save.
    @discardableResult
    func saveSnapshot(message: String, includeUntracked: Bool) async throws -> Bool

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

    /// Submodules declared in `.gitmodules`, with their checkout state.
    func submodules() async throws -> [SubmoduleInfo]
    func initSubmodule(path: String) async throws
    /// `toRemote` moves it to its tracked branch's tip instead of the commit this repository records.
    func updateSubmodule(path: String, toRemote: Bool) async throws
    func fetchSubmodule(path: String) async throws
    func addSubmodule(url: String, path: String, branch: String?) async throws
    /// Deinitializes, removes it from the index and `.gitmodules`, and deletes its clone under `.git/modules`.
    func removeSubmodule(path: String) async throws

    // MARK: Worktrees

    /// Every worktree of the repository, main one first.
    func worktrees() async throws -> [WorktreeInfo]

    /// Forget worktrees whose folders were deleted (`git worktree prune`).
    func pruneWorktrees() async throws

    /// Remove a linked worktree (`git worktree remove <path>`).
    func removeWorktree(path: String, force: Bool) async throws

    // MARK: Blame

    func blame(file: String, revision: String?) async throws -> [BlameEntry]

    // MARK: Reflog

    func reflog(maxCount: Int) async throws -> [ReflogEntry]

    // MARK: Inspection & Local Config (implemented in GitRepository+Inspection.swift)

    /// Files changed by a stash, including its untracked files.
    func stashDiff(index: Int) async throws -> [FileDiff]
    /// File text at `revision`, or the working-tree copy when `revision` is nil.
    func fileContents(path: String, revision: String?) async throws -> String
    /// Raw file bytes at `revision`, for binary content such as images.
    func fileData(path: String, at revision: FileRevision) async throws -> Data
    /// Local branch names fully merged into `base`.
    func mergedBranches(into base: String) async throws -> Set<String>
    /// Commits `branch` has that `base` lacks (ahead) and vice versa (behind).
    func aheadBehind(branch: String, base: String) async throws -> (ahead: Int, behind: Int)
    /// Tip SHA, committer date, author and subject of every local branch.
    func branchTips() async throws -> [BranchTip]
    /// Ahead/behind counts for each named local branch against `base`, keyed by branch name.
    func aheadBehind(branches: [String], base: String) async throws -> [String: AheadBehind]
    /// Commits unique to each side of `base...compare` and the files `compare` changed since the merge base.
    func compareBranches(base: String, compare: String) async throws -> BranchComparison
    /// Value from the repository's local `.git/config`, or nil when unset.
    func localConfigValue(_ key: String) async throws -> String?
    /// Writes a local config value; nil or empty unsets it.
    func setLocalConfigValue(_ key: String, to value: String?) async throws
    func setRemoteURL(_ url: String, forRemote name: String) async throws
    /// `git remote add <name> <url>`.
    func addRemote(name: String, url: String) async throws
    /// `git remote remove <name>`, which also drops its remote-tracking branches.
    func removeRemote(name: String) async throws
    /// Full diff of a pull request against its base.
    func pullRequestDiff(number: Int) async throws -> [FileDiff]
    /// Commits in a pull request.
    func pullRequestCommits(number: Int) async throws -> [CommitInfo]

    // MARK: Pull Requests

    /// The repository's pull requests on its hosting service.
    func pullRequests() async throws -> [PullRequestInfo]
    /// Open and recently merged pull requests, as branch rows.
    func branchPullRequests() async throws -> [BranchPullRequest]
    /// Return full detail for a single pull request number.
    func pullRequestDetail(number: Int) async throws -> PullRequestInfo
    /// Return all comments and reviews for a pull request.
    func pullRequestComments(number: Int) async throws -> [PRComment]
    /// Check out the branch of a pull request.
    func checkoutPullRequest(number: Int) async throws
    /// Close a pull request without merging.
    func closePullRequest(number: Int) async throws
    /// Merge a pull request using the merge strategy.
    func mergePullRequest(number: Int) async throws
    /// The service the repository's remote points at, even without an account for it.
    func hostingService() async -> HostingServiceKind?
    /// The pull request's page on its service.
    func pullRequestWebURL(number: Int) async throws -> URL?
    /// Posts a general comment on a pull request's conversation.
    func commentOnPullRequest(number: Int, body: String) async throws
    /// Comments left on lines of a pull request's diff.
    func pullRequestReviewComments(number: Int) async throws -> [PRReviewComment]
    /// Opens a pull request on the host and returns its web URL.
    func createPullRequest(_ draft: PullRequestDraft) async throws -> String
    /// Pushes a local branch that needn't be checked out to `target` on `remote`, and tracks it (`push -u`).
    func publishBranch(_ name: String, to remote: String, as target: String) async throws
    /// The branch `remote`'s HEAD points at (`refs/remotes/<remote>/HEAD`), if git knows it.
    func defaultBranch(of remote: String) async -> String?

    // MARK: Working Copy

    /// Create a commit; `signOff` adds a `Signed-off-by` trailer (`--signoff`).
    @discardableResult
    func commit(message: String, body: String?, amend: Bool, sign: Bool, signOff: Bool) async throws -> CommitInfo
    /// The effective `user.name` / `user.email`, or `nil` when unset.
    func commitIdentity() async -> CommitIdentity?
    /// Contents of the file git's `commit.template` points at, or `nil` when unset or unreadable.
    func commitTemplate() async -> String?
    /// Branch names for both sides of the in-progress merge/rebase/cherry-pick/revert.
    func operationContext() async -> OperationContext?
    /// Continue the in-progress operation after conflicts are resolved.
    func continueOperation() async throws
    /// Contents of stage 2 (ours) and stage 3 (theirs) for a conflicted file.
    func conflictVersions(path: String) async throws -> ConflictVersions
    /// Resolve a conflicted file by taking one side wholesale and staging it.
    func resolveConflict(path: String, side: ConflictSide) async throws

    // MARK: Git LFS (GitRepository+LFS.swift)

    func lfsStatus() async -> LFSStatus
    /// Which of `paths` the repository's attributes route through the LFS filter.
    func lfsTrackedPaths(among paths: [String]) async -> Set<String>
    /// `git lfs track`, staging `.gitattributes`; `literal` tracks one file rather than a glob.
    func trackWithLFS(pattern: String, literal: Bool) async throws

    // MARK: git-flow (GitRepository+Flow.swift)

    /// nil until git-flow is initialized in this repository.
    func gitFlowConfig() async -> GitFlowConfig?
    func initializeGitFlow(_ config: GitFlowConfig) async throws
    /// `base` overrides where the branch starts; nil uses git-flow's default for `kind`.
    func startFlowBranch(_ kind: GitFlowKind, name: String, base: String?, config: GitFlowConfig) async throws
    func finishFlowBranch(_ kind: GitFlowKind, name: String, config: GitFlowConfig, options: GitFlowFinishOptions) async throws

    // MARK: git-svn (GitRepository+SVN.swift)

    func svnStatus() async -> SVNStatus
    /// `git svn rebase`, or `git svn fetch` when `rebase` is false.
    func svnFetch(rebase: Bool) async throws
    func svnDcommit() async throws

    // MARK: Branch Sync (GitRepository+BranchSync.swift)

    /// Moves a local branch that isn't checked out to a remote branch, fast-forward only.
    func fastForward(branch: String, fromRemote remote: String, branch remoteBranch: String) async throws
    /// Pushes any local branch, checked out or not, to `remoteBranch` on `remote`.
    func push(branch: String, to remote: String, as remoteBranch: String, setUpstream: Bool) async throws

    // MARK: File Actions (implemented in GitRepository+FileActions.swift)

    /// Appends gitignore patterns to `.gitignore`, or to `.git/info/exclude` when `localOnly`.
    func ignore(patterns: [String], localOnly: Bool) async throws
    /// Removes paths from the index but keeps them on disk (`git rm --cached`).
    func stopTracking(paths: [String]) async throws
    /// Renames or moves a file: `git mv` when tracked, a plain move when untracked.
    func moveFile(from source: String, to destination: String) async throws
    /// Writes `revisionPath` as it was at `revision` into the working copy at `path`, leaving the index alone.
    func restoreFile(_ path: String, from revision: String, revisionPath: String) async throws

    // MARK: Patches (implemented in GitRepository+Patches.swift)

    /// The staged or unstaged changes of `paths` as an applicable patch; unstaged includes untracked files.
    func patch(paths: [String], staged: Bool) async throws -> String
    /// `git apply` of a patch file; `toIndex` also stages it, `checkOnly` only reports whether it applies.
    func applyPatch(at file: URL, toIndex: Bool, checkOnly: Bool) async throws
}

// MARK: - GitRepositoryProtocol Default Arguments

/// Convenience overloads that supply `sign: false` so existing call sites
/// that were written before signing support was added continue to compile
/// without modification.
extension GitRepositoryProtocol {

    // Defaults so lightweight test doubles only implement what they exercise.
    // TODO: A method GitRepository forgets to implement silently falls back to one of these.
    func log(maxCount: Int, skip: Int, revisions: [String]) async throws -> [CommitInfo] {
        try await log(maxCount: maxCount, skip: skip, branch: revisions.first)
    }

    func commits(in revision: String, notIn base: String) async throws -> Set<String> { [] }
    func isAncestor(_ commit: String, of descendant: String) async -> Bool { false }
    func formatPatch(commits: [String]) async throws -> String { "" }
    func archive(revision: String, to url: URL) async throws {}

    @discardableResult
    func commit(message: String, body: String?, amend: Bool, sign: Bool, signOff: Bool) async throws -> CommitInfo {
        try await commit(message: message, body: body, amend: amend, sign: sign)
    }

    func commitIdentity() async -> CommitIdentity? { nil }
    func operationContext() async -> OperationContext? { nil }
    func continueOperation() async throws {}
    func conflictVersions(path: String) async throws -> ConflictVersions { ConflictVersions() }
    func resolveConflict(path: String, side: ConflictSide) async throws {}

    @discardableResult
    func commit(message: String, body: String?, amend: Bool) async throws -> CommitInfo {
        try await commit(message: message, body: body, amend: amend, sign: false)
    }

    @discardableResult
    func createTag(name: String, at sha: String?, message: String?) async throws -> TagInfo {
        try await createTag(name: name, at: sha, message: message, sign: false)
    }

    func filesInCommit(_ sha: String) async throws -> [String] { [] }

    func diffForCommit(_ sha: String, path: String) async throws -> [FileDiff] {
        try await diffForCommit(sha).filter { $0.path == path || $0.diff?.oldPath == path }
    }

    func stashDiff(index: Int) async throws -> [FileDiff] { [] }
    func submodules() async throws -> [SubmoduleInfo] { [] }
    func initSubmodule(path: String) async throws {}
    func updateSubmodule(path: String, toRemote: Bool) async throws {}
    func fetchSubmodule(path: String) async throws {}
    func addSubmodule(url: String, path: String, branch: String?) async throws {}
    func removeSubmodule(path: String) async throws {}
    func worktrees() async throws -> [WorktreeInfo] { [] }
    @discardableResult
    func createBranch(name: String, from: String?, checkout: Bool, track: Bool, parent: String?) async throws -> BranchInfo {
        try await createBranch(name: name, from: from, checkout: checkout)
    }
    func branchParents() async throws -> [String: String] { [:] }
    func branchPullRequests() async throws -> [BranchPullRequest] { [] }
    func pull(remote: String?, branch: String?, strategy: PullStrategy, options: PullOptions,
              progress: (@Sendable (Double) -> Void)?) async throws {
        try await pull(remote: remote, strategy: strategy, progress: progress)
    }
    func push(remote: String, branch: String, forceWithLease: Bool, setUpstream: Bool, options: PushOptions,
              progress: (@Sendable (Double) -> Void)?) async throws {
        try await push(remote: remote, forceWithLease: forceWithLease, setUpstream: setUpstream, progress: progress)
    }
    func pruneWorktrees() async throws {}
    func fileContents(path: String, revision: String?) async throws -> String { "" }
    func fileData(path: String, at revision: FileRevision) async throws -> Data { Data() }
    func mergedBranches(into base: String) async throws -> Set<String> { [] }
    func aheadBehind(branch: String, base: String) async throws -> (ahead: Int, behind: Int) { (0, 0) }
    func branchTips() async throws -> [BranchTip] { [] }
    func aheadBehind(branches: [String], base: String) async throws -> [String: AheadBehind] { [:] }
    func compareBranches(base: String, compare: String) async throws -> BranchComparison { BranchComparison() }
    func defaultPullStrategy() async -> PullStrategy { .merge }
    func localConfigValue(_ key: String) async throws -> String? { nil }
    func setLocalConfigValue(_ key: String, to value: String?) async throws {}
    func setRemoteURL(_ url: String, forRemote name: String) async throws {}
    func addRemote(name: String, url: String) async throws {}
    func setUpstream(of branch: String, to remoteBranch: String?) async throws {}
    func removeRemote(name: String) async throws {}
    func pullRequestDiff(number: Int) async throws -> [FileDiff] { [] }
    func pullRequestCommits(number: Int) async throws -> [CommitInfo] { [] }
    func lfsStatus() async -> LFSStatus { LFSStatus() }
    func lfsTrackedPaths(among paths: [String]) async -> Set<String> { [] }
    func trackWithLFS(pattern: String, literal: Bool) async throws {}
    func gitFlowConfig() async -> GitFlowConfig? { nil }
    func initializeGitFlow(_ config: GitFlowConfig) async throws {}
    func startFlowBranch(_ kind: GitFlowKind, name: String, base: String?, config: GitFlowConfig) async throws {}
    func finishFlowBranch(_ kind: GitFlowKind, name: String, config: GitFlowConfig, options: GitFlowFinishOptions) async throws {}
    func svnStatus() async -> SVNStatus { SVNStatus() }
    func svnFetch(rebase: Bool) async throws {}
    func svnDcommit() async throws {}
    func fastForward(branch: String, fromRemote remote: String, branch remoteBranch: String) async throws {}
    func push(branch: String, to remote: String, as remoteBranch: String, setUpstream: Bool) async throws {}
    func createPullRequest(_ draft: PullRequestDraft) async throws -> String { "" }
    func commentOnPullRequest(number: Int, body: String) async throws {}
    func hostingService() async -> HostingServiceKind? { .github }
    func pullRequestWebURL(number: Int) async throws -> URL? { nil }
    func pullRequestReviewComments(number: Int) async throws -> [PRReviewComment] { [] }
    func publishBranch(_ name: String, to remote: String, as target: String) async throws {}
    func defaultBranch(of remote: String) async -> String? { nil }
}
