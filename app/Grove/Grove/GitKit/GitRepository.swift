// GitKit/GitRepository.swift
// Grove
//
// Concrete implementation of GitRepositoryProtocol.
// All git operations are delegated to the git CLI via GitShell.
//
// Threading model:
//   - The class is @MainActor (required by GitRepositoryProtocol).
//   - Heavy I/O runs inside `Task { }` detached blocks using `nonisolated`
//     helpers, then results are returned to the caller on the main actor.
//   - GitShell is `Sendable` (final, immutable after init) so it crosses
//     actor boundaries safely.

import Foundation
import Observation
import os

// MARK: - GitRepositoryError

/// Domain errors thrown by ``GitRepository``.
enum GitRepositoryError: LocalizedError {
    case notAGitRepository(URL)
    case invalidCommitMessage
    case branchNotFound(String)
    case commitNotFound(String)
    case commitReadbackFailed
    case tagNotFound(String)
    case cannotDeleteCurrentBranch
    case remoteOperationFailed(String)
    case stashIndexOutOfRange(Int)
    case applyPatchFailed(String)
    case historyRewriteConflict

    var errorDescription: String? {
        switch self {
        case .notAGitRepository(let url):
            return "'\(url.path)' is not a Git repository."
        case .invalidCommitMessage:
            return "A commit message is required."
        case .branchNotFound(let name):
            return "Branch '\(name)' not found."
        case .commitNotFound(let sha):
            return "Commit '\(sha)' not found."
        case .commitReadbackFailed:
            return "Failed to read back the newly created commit."
        case .tagNotFound(let name):
            return "Tag '\(name)' not found."
        case .cannotDeleteCurrentBranch:
            return "Cannot delete the currently checked-out branch."
        case .remoteOperationFailed(let detail):
            return "Remote operation failed: \(detail)"
        case .stashIndexOutOfRange(let index):
            return "Stash index \(index) is out of range."
        case .applyPatchFailed(let detail):
            return "Failed to apply patch: \(detail)"
        case .historyRewriteConflict:
            return "Newer commits depend on these changes, so rewriting history would conflict. Nothing was changed."
        }
    }
}

// MARK: - GitRepository

/// Real Git repository backed by the `git` CLI.
///
/// Conforms to ``GitRepositoryProtocol`` and is ``Observable`` via the
/// `@Observable` macro. All protocol methods are `async throws` and forward
/// work to ``GitShell``, returning on the main actor.
@MainActor
@Observable
final class GitRepository: GitRepositoryProtocol {

    // MARK: Observable Properties

    let path: URL
    let displayName: String
    var currentBranch: BranchInfo?
    var repositoryState: RepositoryState = .normal

    // MARK: Private

    private let shell: GitShell

    // MARK: Init

    /// Open an existing git repository at `path`.
    ///
    /// - Parameter path: Absolute URL of the repository working directory.
    /// - Throws: ``GitRepositoryError/notAGitRepository`` if `path` is not
    ///   inside a git repo.
    init(path: URL) async throws {
        self.path        = path
        self.displayName = path.lastPathComponent
        self.shell       = GitShell(workingDirectory: path)

        Logger.gitRepository.info("Opening repository at \(path.path, privacy: .public)")

        // Verify this is actually a git repo.
        let result = try await shell.runAllowingFailure(["rev-parse", "--git-dir"])
        if !result.isSuccess {
            Logger.gitRepository.error("Not a git repository: \(path.path, privacy: .public)")
            throw GitRepositoryError.notAGitRepository(path)
        }

        // Load initial state.
        currentBranch  = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)

        Logger.gitRepository.info(
            "Repository opened: \(path.lastPathComponent, privacy: .public) on \(self.currentBranch?.name ?? "detached HEAD", privacy: .public) [state: \(self.repositoryState.logDescription, privacy: .public)]"
        )
    }

    // MARK: - Status

    func refreshStatus() async throws {
        Logger.gitRepository.debug("Refreshing status for \(self.displayName, privacy: .public)")
        let previousState = repositoryState
        // Status is computed on demand; this triggers a re-read of current branch.
        currentBranch   = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)
        if repositoryState != previousState {
            Logger.gitRepository.notice(
                "\(self.displayName, privacy: .public) state: \(previousState.logDescription, privacy: .public) → \(self.repositoryState.logDescription, privacy: .public)"
            )
        }
    }

    func status() async throws -> [StatusEntry] {
        let result = try await shell.run(["--no-optional-locks", "status", "--porcelain=v2", "-uall"])
        return StatusParser.parse(result.stdout)
    }

    func listTrackedFiles() async throws -> [String] {
        let result = try await shell.run(["ls-files"])
        return result.stdout
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    // MARK: - Staging

    func stage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await shell.run(["add", "--"] + paths)
    }

    func unstage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        // Use `git restore --staged` (git 2.23+); fallback: `git reset HEAD --`
        let result = try await shell.runAllowingFailure(["restore", "--staged", "--"] + paths)
        if !result.isSuccess {
            try await shell.run(["reset", "HEAD", "--"] + paths)
        }
    }

    func stageHunk(_ hunk: HunkData, in file: String) async throws {
        let patch = DiffParser.buildPatch(from: hunk, filePath: file)
        try await applyPatch(patch, cached: true)
    }

    func unstageHunk(_ hunk: HunkData, in file: String) async throws {
        let patch = DiffParser.buildPatch(from: hunk, filePath: file)
        try await applyPatch(patch, cached: true, reverse: true)
    }

    func stageLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws {
        let patch = DiffParser.buildPatch(from: lines, in: hunk, filePath: file)
        try await applyPatch(patch, cached: true)
    }

    func unstageLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws {
        let patch = DiffParser.buildPatch(from: lines, in: hunk, filePath: file)
        try await applyPatch(patch, cached: true, reverse: true)
    }

    func stageAll() async throws {
        try await shell.run(["add", "-A"])
    }

    func unstageAll() async throws {
        try await shell.run(["reset", "HEAD"])
    }

    func discardChanges(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        // Untracked files have nothing to restore; they are deleted instead.
        let untrackedOutput = try await shell.run(["ls-files", "--others", "--exclude-standard", "-z", "--"] + paths).stdout
        let untracked = Set(untrackedOutput.split(separator: "\0").map(String.init))
        let tracked = paths.filter { !untracked.contains($0) }
        if !untracked.isEmpty {
            try await shell.run(["clean", "-f", "--"] + Array(untracked))
        }
        if !tracked.isEmpty {
            // Restoring index and worktree from HEAD also drops newly added files.
            try await shell.run(["restore", "--source=HEAD", "--staged", "--worktree", "--"] + tracked)
        }
    }

    func discardHunk(_ hunk: HunkData, in file: String) async throws {
        // Apply a reverse patch to the working tree (no --cached).
        let patch = DiffParser.buildReversePatch(from: hunk, filePath: file)
        try await applyPatch(patch, cached: false, reverse: false)
    }

    func discardLines(_ lines: [DiffLine], in hunk: HunkData, file: String) async throws {
        // Apply a reverse patch for the selected lines to the working tree.
        let patch = DiffParser.buildPatch(from: lines, in: hunk, filePath: file)
        try await applyPatch(patch, cached: false, reverse: true)
    }

    // MARK: - Diff

    func diff(for entry: StatusEntry, staged: Bool, ignoreWhitespace: Bool = false) async throws -> DiffResult {
        var args: [String]
        if staged {
            // diff HEAD → index (what would be committed)
            args = ["diff", "--cached", "-U3"]
        } else {
            // diff index → working tree (unstaged changes)
            args = ["diff", "-U3"]
        }
        if ignoreWhitespace { args.append("-w") }
        let output: String
        if !staged && entry.workdirStatus == .untracked {
            // Untracked files are invisible to `git diff`; compare against an empty file. Exit 1 means "differs".
            let result = try await shell.runAllowingFailure(args + ["--no-index", "--", "/dev/null", entry.path])
            guard result.exitCode <= 1 else {
                throw GitShellError.nonZeroExit(command: "git diff --no-index", exitCode: result.exitCode, stderr: result.stderr)
            }
            output = result.stdout
        } else {
            output = try await shell.run(args + ["--", entry.path]).stdout
        }
        return DiffParser.parseSingleFile(output) ?? DiffResult(
            filePath: entry.path,
            oldPath: nil,
            isBinary: false,
            hunks: [],
            stats: DiffStats(additions: 0, deletions: 0)
        )
    }

    func diffForCommit(_ sha: String) async throws -> [FileDiff] {
        // `show` handles root commits; merges diff against their first parent.
        let base = ["show", "--format=", "-M", "--diff-merges=first-parent", "--no-ext-diff", "--no-color"]
        let diffResult = try await shell.run(base + ["-U3", sha, "--"])
        // Without the final newline the parser doesn't read a phantom empty context line.
        let output = diffResult.stdout.hasSuffix("\n") ? String(diffResult.stdout.dropLast()) : diffResult.stdout
        let diffs = DiffParser.parse(output)
        let statusResult = try await shell.run(base + ["--name-status", sha, "--"])
        let statusMap = parseNameStatus(statusResult.stdout)

        return diffs.map { diff in
            let status = statusMap[diff.filePath] ?? .modified
            return FileDiff(
                path: diff.filePath,
                status: status,
                diff: diff,
                stats: diff.stats
            )
        }
    }

    func filesInCommit(_ sha: String) async throws -> [String] {
        let result = try await shell.run(["ls-tree", "-r", "--name-only", "--full-tree", sha])
        return result.stdout.split(separator: "\n").map(String.init)
    }

    // MARK: - Commits

    @discardableResult
    func commit(message: String, body: String?, amend: Bool, sign: Bool = false) async throws -> CommitInfo {
        try await commit(message: message, body: body, amend: amend, sign: sign, signOff: false)
    }

    @discardableResult
    func commit(message: String, body: String?, amend: Bool, sign: Bool, signOff: Bool) async throws -> CommitInfo {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.gitRepository.error("Commit attempted with empty message in \(self.displayName, privacy: .public)")
            throw GitRepositoryError.invalidCommitMessage
        }

        let operation = amend ? "amend" : "commit"
        Logger.gitRepository.info("\(operation, privacy: .public) in \(self.displayName, privacy: .public)")

        let fullMessage: String
        if let body, !body.isEmpty {
            fullMessage = "\(message)\n\n\(body)"
        } else {
            fullMessage = message
        }

        var args = ["commit", "-m", fullMessage]
        if amend { args.append("--amend") }
        if sign { args.append("-S") }
        if signOff { args.append("--signoff") }
        try await shell.run(args)

        // Return the newly created commit.
        let commits = try await log(maxCount: 1, skip: 0, branch: nil)
        guard let commit = commits.first else {
            throw GitRepositoryError.commitReadbackFailed
        }

        Logger.gitRepository.info(
            "\(operation, privacy: .public) succeeded: \(commit.shortSHA, privacy: .public) in \(self.displayName, privacy: .public)"
        )

        // Refresh branch state.
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        return commit
    }

    func isSigningConfigured() async throws -> Bool {
        // Check if commit.gpgsign is explicitly set to "true".
        let gpgsignResult = try await shell.runAllowingFailure(["config", "--get", "commit.gpgsign"])
        if gpgsignResult.isSuccess {
            let value = gpgsignResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if value == "true" { return true }
        }

        // Fall back to checking whether user.signingkey has a non-empty value.
        let signingKeyResult = try await shell.runAllowingFailure(["config", "--get", "user.signingkey"])
        if signingKeyResult.isSuccess {
            let key = signingKeyResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return !key.isEmpty
        }

        return false
    }

    func log(maxCount: Int, skip: Int, branch: String?) async throws -> [CommitInfo] {
        var args = [
            "log",
            "--format=\(LogParser.formatString)",
            "--date-order",
            "-\(maxCount)",
            "--skip=\(skip)"
        ]
        if let branch {
            args.append(branch)
        }
        let result = try await shell.run(args)
        return LogParser.parse(result.stdout)
    }

    func fileLog(path: String, maxCount: Int) async throws -> [CommitInfo] {
        let args = [
            "log",
            "--format=\(LogParser.formatString)",
            "-\(maxCount)",
            "--follow",
            "--",
            path
        ]
        let result = try await shell.run(args)
        return LogParser.parse(result.stdout)
    }

    func commitDetail(_ sha: String) async throws -> CommitInfo {
        let result = try await shell.run(
            ["log", "--format=\(LogParser.formatString)", "-1", sha]
        )
        let commits = LogParser.parse(result.stdout)
        guard let commit = commits.first else {
            throw GitRepositoryError.commitNotFound(sha)
        }
        return commit
    }

    // MARK: - Branches

    func localBranches() async throws -> [BranchInfo] {
        try await fetchBranches(refPattern: "refs/heads/")
    }

    func remoteBranches() async throws -> [BranchInfo] {
        try await fetchBranches(refPattern: "refs/remotes/")
    }

    @discardableResult
    func createBranch(name: String, from: String?, checkout: Bool) async throws -> BranchInfo {
        var args: [String]
        if checkout {
            args = ["checkout", "-b", name]
            if let from { args.append(from) }
        } else {
            args = ["branch", name]
            if let from { args.append(from) }
        }
        try await shell.run(args)

        let branches = try await localBranches()
        guard let branch = branches.first(where: { $0.name == name }) else {
            throw GitRepositoryError.branchNotFound(name)
        }

        if checkout {
            currentBranch = branch
        }
        return branch
    }

    func checkout(branch: String) async throws {
        try await shell.run(["checkout", branch])
        currentBranch   = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)
    }

    func deleteBranch(name: String, force: Bool) async throws {
        let flag = force ? "-D" : "-d"
        try await shell.run(["branch", flag, name])
    }

    func deleteRemoteBranch(name: String, remote: String) async throws {
        try await shell.run(["push", remote, "--delete", name])
    }

    func renameBranch(oldName: String, newName: String) async throws {
        try await shell.run(["branch", "-m", oldName, newName])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
    }

    // MARK: - Remotes

    func remotes() async throws -> [RemoteInfo] {
        let result = try await shell.run(["remote", "-v"])
        return parseRemoteVerbose(result.stdout)
    }

    func fetch(remote: String?, progress: (@Sendable (Double) -> Void)?) async throws {
        Logger.gitRepository.info(
            "Fetching \(remote ?? "all remotes", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        var args = ["fetch", "--prune"]
        if let remote { args.append(remote) }
        try await shell.run(args)
        progress?(1.0)
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        Logger.gitRepository.info("Fetch complete in \(self.displayName, privacy: .public)")
    }

    func pull(remote: String?, rebase: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        let strategy = rebase ? "rebase" : "merge"
        Logger.gitRepository.info(
            "Pulling (\(strategy, privacy: .public)) from \(remote ?? "default", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        var args = ["pull"]
        if rebase { args.append("--rebase") }
        if let remote { args.append(remote) }
        try await shell.run(args)
        progress?(1.0)
        currentBranch   = try? await Self.loadCurrentBranch(shell: shell)
        let previousState = repositoryState
        repositoryState = await Self.loadRepositoryState(path: path)
        Logger.gitRepository.info("Pull complete in \(self.displayName, privacy: .public)")
        if repositoryState != previousState {
            Logger.gitRepository.notice(
                "\(self.displayName, privacy: .public) state after pull: \(previousState.logDescription, privacy: .public) → \(self.repositoryState.logDescription, privacy: .public)"
            )
        }
    }

    func push(remote: String?, force: Bool, forceWithLease: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        let forceDescription = forceWithLease ? " --force-with-lease" : (force ? " --force" : "")
        Logger.gitRepository.info(
            "Pushing\(forceDescription, privacy: .public) to \(remote ?? "default", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        var args = ["push"]
        if forceWithLease {
            args.append("--force-with-lease")
        } else if force {
            args.append("--force")
        }
        if let remote { args.append(remote) }
        try await shell.run(args)
        progress?(1.0)
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        Logger.gitRepository.info("Push complete in \(self.displayName, privacy: .public)")
    }

    func sync(remote: String?, rebase: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        Logger.gitRepository.info(
            "Syncing with \(remote ?? "default", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await fetch(remote: remote, progress: nil)
        progress?(0.33)
        try await pull(remote: remote, rebase: rebase, progress: nil)
        progress?(0.66)
        try await push(remote: remote, force: false, forceWithLease: false, progress: nil)
        progress?(1.0)
        Logger.gitRepository.info("Sync complete in \(self.displayName, privacy: .public)")
    }

    // MARK: - Merge / Rebase

    func merge(branch: String) async throws {
        Logger.gitRepository.info(
            "Merging \(branch, privacy: .public) into \(self.currentBranch?.name ?? "HEAD", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["merge", branch])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        let mergeStateBefore = repositoryState
        repositoryState = await Self.loadRepositoryState(path: path)
        if repositoryState != mergeStateBefore {
            Logger.gitRepository.notice(
                "\(self.displayName, privacy: .public) state after merge: \(mergeStateBefore.logDescription, privacy: .public) → \(self.repositoryState.logDescription, privacy: .public)"
            )
        }
    }

    func abortMerge() async throws {
        Logger.gitRepository.info("Aborting merge in \(self.displayName, privacy: .public)")
        try await shell.run(["merge", "--abort"])
        let mergeStateBefore = repositoryState
        repositoryState = .normal
        Logger.gitRepository.notice(
            "\(self.displayName, privacy: .public) state: \(mergeStateBefore.logDescription, privacy: .public) → normal"
        )
    }

    func rebase(onto: String) async throws {
        Logger.gitRepository.info(
            "Rebasing onto \(onto, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["rebase", onto])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        let rebaseStateBefore = repositoryState
        repositoryState = await Self.loadRepositoryState(path: path)
        if repositoryState != rebaseStateBefore {
            Logger.gitRepository.notice(
                "\(self.displayName, privacy: .public) state after rebase: \(rebaseStateBefore.logDescription, privacy: .public) → \(self.repositoryState.logDescription, privacy: .public)"
            )
        }
    }

    func abortRebase() async throws {
        Logger.gitRepository.info("Aborting rebase in \(self.displayName, privacy: .public)")
        try await shell.run(["rebase", "--abort"])
        let rebaseStateBefore = repositoryState
        repositoryState = .normal
        Logger.gitRepository.notice(
            "\(self.displayName, privacy: .public) state: \(rebaseStateBefore.logDescription, privacy: .public) → normal"
        )
    }

    func continueRebase() async throws {
        Logger.gitRepository.info("Continuing rebase in \(self.displayName, privacy: .public)")
        try await shell.run(
            ["rebase", "--continue"],
            environment: ["GIT_EDITOR": "true"]  // Accept default commit message.
        )
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        let continueStateBefore = repositoryState
        repositoryState = await Self.loadRepositoryState(path: path)
        if repositoryState != continueStateBefore {
            Logger.gitRepository.notice(
                "\(self.displayName, privacy: .public) state after continue-rebase: \(continueStateBefore.logDescription, privacy: .public) → \(self.repositoryState.logDescription, privacy: .public)"
            )
        }
    }

    func conflicts() async throws -> [StatusEntry] {
        let all = try await status()
        return all.filter {
            $0.indexStatus == .conflicted || $0.workdirStatus == .conflicted
        }
    }

    // MARK: - Cherry-pick

    func cherryPick(commit: String) async throws {
        Logger.gitRepository.info(
            "Cherry-picking \(commit, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["cherry-pick", commit])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        let stateBefore = repositoryState
        repositoryState = await Self.loadRepositoryState(path: path)
        if repositoryState != stateBefore {
            Logger.gitRepository.notice(
                "\(self.displayName, privacy: .public) state after cherry-pick: \(stateBefore.logDescription, privacy: .public) → \(self.repositoryState.logDescription, privacy: .public)"
            )
        }
    }

    func abortCherryPick() async throws {
        Logger.gitRepository.info("Aborting cherry-pick in \(self.displayName, privacy: .public)")
        try await shell.run(["cherry-pick", "--abort"])
        let stateBefore = repositoryState
        repositoryState = .normal
        Logger.gitRepository.notice(
            "\(self.displayName, privacy: .public) state: \(stateBefore.logDescription, privacy: .public) → normal"
        )
    }

    // MARK: - Revert

    func revert(commit: String) async throws {
        Logger.gitRepository.info(
            "Reverting \(commit, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        // --no-edit prevents git from opening an editor for the revert message.
        try await shell.run(["revert", "--no-edit", commit])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        let stateBefore = repositoryState
        repositoryState = await Self.loadRepositoryState(path: path)
        if repositoryState != stateBefore {
            Logger.gitRepository.notice(
                "\(self.displayName, privacy: .public) state after revert: \(stateBefore.logDescription, privacy: .public) → \(self.repositoryState.logDescription, privacy: .public)"
            )
        }
    }

    func abortRevert() async throws {
        Logger.gitRepository.info("Aborting revert in \(self.displayName, privacy: .public)")
        try await shell.run(["revert", "--abort"])
        let stateBefore = repositoryState
        repositoryState = .normal
        Logger.gitRepository.notice(
            "\(self.displayName, privacy: .public) state: \(stateBefore.logDescription, privacy: .public) → normal"
        )
    }

    // MARK: - Bisect

    func bisectStart() async throws {
        Logger.gitRepository.info("Starting bisect in \(self.displayName, privacy: .public)")
        try await shell.run(["bisect", "start"])
        repositoryState = await Self.loadRepositoryState(path: path)
    }

    func bisectBad(commit: String?) async throws {
        var args = ["bisect", "bad"]
        if let commit { args.append(commit) }
        Logger.gitRepository.info(
            "Bisect bad\(commit.map { " \($0)" } ?? "", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(args)
    }

    func bisectGood(commit: String?) async throws {
        var args = ["bisect", "good"]
        if let commit { args.append(commit) }
        Logger.gitRepository.info(
            "Bisect good\(commit.map { " \($0)" } ?? "", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(args)
    }

    func bisectReset() async throws {
        Logger.gitRepository.info("Resetting bisect in \(self.displayName, privacy: .public)")
        try await shell.run(["bisect", "reset"])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        let stateBefore = repositoryState
        repositoryState = .normal
        Logger.gitRepository.notice(
            "\(self.displayName, privacy: .public) state: \(stateBefore.logDescription, privacy: .public) → normal"
        )
    }

    func bisectLog() async throws -> [String] {
        let result = try await shell.run(["bisect", "log"])
        return result.stdout
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
    }

    // MARK: - Interactive Rebase

    func rebaseInteractive(onto: String, commitCount: Int) async throws {
        Logger.gitRepository.info(
            "Interactive rebase of \(commitCount, privacy: .public) commits onto \(onto, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        // GIT_SEQUENCE_EDITOR=true accepts the default todo list unchanged.
        try await shell.run(
            ["rebase", "-i", "\(onto)~\(commitCount)"],
            environment: ["GIT_SEQUENCE_EDITOR": "true"]
        )
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)
    }

    func squashCommits(_ commits: [String], message: String) async throws {
        guard commits.count >= 2 else { return }
        Logger.gitRepository.info(
            "Squashing \(commits.count, privacy: .public) commits in \(self.displayName, privacy: .public)"
        )
        try await rewriteHistory(from: commits[0], action: "squash", targets: Array(commits.dropFirst()), message: message)
        Logger.gitRepository.info("Squash complete in \(self.displayName, privacy: .public)")
    }

    func rewordCommit(_ commit: String, newMessage: String) async throws {
        Logger.gitRepository.info(
            "Rewording \(commit, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await rewriteHistory(from: commit, action: "reword", targets: [commit], message: newMessage)
        Logger.gitRepository.info("Reword complete in \(self.displayName, privacy: .public)")
    }

    func dropCommit(_ commit: String) async throws {
        Logger.gitRepository.info(
            "Dropping \(commit, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await rewriteHistory(from: commit, action: "drop", targets: [commit], message: nil)
        Logger.gitRepository.info("Drop complete in \(self.displayName, privacy: .public)")
    }

    /// Scripted `rebase -i` from `oldest`'s parent that applies `action` to each target's pick line.
    private func rewriteHistory(from oldest: String, action: String, targets: [String], message: String?) async throws {
        // Todo lines carry abbreviated SHAs, so match them as prefixes of the full target SHAs.
        let todoScript = """
            #!/bin/sh
            TODO="$1"
            TMP="$TODO.grove"
            : > "$TMP"
            while IFS= read -r line || [ -n "$line" ]; do
                cmd=${line%% *}
                rest=${line#* }
                sha=${rest%% *}
                if [ "$cmd" = pick ] && [ -n "$sha" ]; then
                    for target in \(targets.joined(separator: " ")); do
                        case "$target" in
                            "$sha"*)
                                if [ "\(action)" = drop ]; then continue 2; fi
                                line="\(action) $rest" ;;
                        esac
                    done
                fi
                printf '%s\\n' "$line" >> "$TMP"
            done < "$TODO"
            mv "$TMP" "$TODO"
            """
        let todoURL = try writeTemporaryScript(todoScript)
        defer { try? FileManager.default.removeItem(at: todoURL) }

        var environment = ["GIT_SEQUENCE_EDITOR": todoURL.path, "GIT_EDITOR": "true"]
        var editorURL: URL?
        if let message {
            let url = try writeTemporaryScript("#!/bin/sh\nprintf '%s\\n' \(shellEscape(message)) > \"$1\"\n")
            environment["GIT_EDITOR"] = url.path
            editorURL = url
        }
        defer { if let editorURL { try? FileManager.default.removeItem(at: editorURL) } }

        let parentResult = try await shell.runAllowingFailure(["rev-parse", "--verify", "--quiet", "\(oldest)^"])
        let base = parentResult.isSuccess
            ? [parentResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)]
            : ["--root"]

        do {
            try await shell.run(["rebase", "-i", "--rebase-merges"] + base, environment: environment)
        } catch {
            // A conflict leaves a half-done rebase; undo it so the branch is exactly as before.
            let stopped = await Self.loadRepositoryState(path: path) != .normal
            if stopped { _ = try? await shell.runAllowingFailure(["rebase", "--abort"]) }
            repositoryState = await Self.loadRepositoryState(path: path)
            currentBranch = try? await Self.loadCurrentBranch(shell: shell)
            throw stopped ? GitRepositoryError.historyRewriteConflict : error
        }
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)
    }

    // MARK: - Reset

    func resetToCommit(_ commit: String, mode: ResetMode) async throws {
        Logger.gitRepository.info(
            "Resetting (\(mode.rawValue, privacy: .public)) to \(commit, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["reset", "--\(mode.rawValue)", commit])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        Logger.gitRepository.info("Reset complete in \(self.displayName, privacy: .public)")
    }

    // MARK: - Clean

    func cleanUntracked(directories: Bool, force: Bool) async throws {
        Logger.gitRepository.info(
            "Cleaning untracked\(directories ? " (+ dirs)" : "", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        var args = ["clean"]
        if force { args.append("-f") }
        if directories { args.append("-d") }
        try await shell.run(args)
        Logger.gitRepository.info("Clean complete in \(self.displayName, privacy: .public)")
    }

    // MARK: - Stash

    func stashes() async throws -> [StashEntry] {
        let result = try await shell.run(
            ["stash", "list", "--format=\(StashParser.formatString)"]
        )
        return StashParser.parse(result.stdout)
    }

    func stashCreate(message: String?, includeUntracked: Bool, paths: [String]? = nil) async throws {
        let pathDesc = paths.map { " (\($0.count) files)" } ?? ""
        Logger.gitRepository.info(
            "Creating stash\(message.map { " '\($0)'" } ?? "")\(pathDesc, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        var args = ["stash", "push"]
        if includeUntracked { args.append("--include-untracked") }
        if let message {
            args += ["-m", message]
        }
        // When specific paths are provided, append them after the -- separator.
        if let paths, !paths.isEmpty {
            args += ["--"] + paths
        }
        try await shell.run(args)
        Logger.gitRepository.info("Stash created in \(self.displayName, privacy: .public)")
    }

    func stashApply(index: Int, drop: Bool) async throws {
        let operation = drop ? "pop" : "apply"
        Logger.gitRepository.info(
            "Stash \(operation, privacy: .public) stash@{\(index, privacy: .public)} in \(self.displayName, privacy: .public)"
        )
        let ref = "stash@{\(index)}"
        if drop {
            try await shell.run(["stash", "pop", ref])
        } else {
            try await shell.run(["stash", "apply", ref])
        }
        repositoryState = await Self.loadRepositoryState(path: path)
    }

    func stashDrop(index: Int) async throws {
        try await shell.run(["stash", "drop", "stash@{\(index)}"])
    }

    // MARK: - Tags

    func tags() async throws -> [TagInfo] {
        let result = try await shell.run([
            "for-each-ref",
            "--sort=-creatordate",
            "--format=%(refname:short)%00%(objectname:short)%00%(objecttype)%00%(*objectname:short)%00%(contents:subject)%00%(taggername)%00%(taggerdate:iso-strict)",
            "refs/tags/"
        ])
        return parseTagList(result.stdout)
    }

    @discardableResult
    func createTag(name: String, at sha: String?, message: String?, sign: Bool = false) async throws -> TagInfo {
        var args: [String]
        if sign {
            // -s implies an annotated tag and uses the configured signing key.
            args = ["tag", "-s", name]
            if let message { args += ["-m", message] }
        } else if let message {
            args = ["tag", "-a", name, "-m", message]
        } else {
            args = ["tag", name]
        }
        if let sha { args.append(sha) }
        try await shell.run(args)

        let allTags = try await tags()
        guard let tag = allTags.first(where: { $0.name == name }) else {
            throw GitRepositoryError.tagNotFound(name)
        }
        return tag
    }

    func deleteTag(name: String) async throws {
        try await shell.run(["tag", "-d", name])
    }

    func pushTag(name: String, remote: String?) async throws {
        let remoteName = remote ?? "origin"
        Logger.gitRepository.info(
            "Pushing tag '\(name, privacy: .public)' to \(remoteName, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["push", remoteName, "refs/tags/\(name)"])
        Logger.gitRepository.info("Tag push complete in \(self.displayName, privacy: .public)")
    }

    func pushAllTags(remote: String?) async throws {
        let remoteName = remote ?? "origin"
        Logger.gitRepository.info(
            "Pushing all tags to \(remoteName, privacy: .public) in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["push", remoteName, "--tags"])
        Logger.gitRepository.info("All tags pushed in \(self.displayName, privacy: .public)")
    }

    // MARK: - Submodules

    func updateSubmodule(path: String) async throws {
        Logger.gitRepository.info(
            "Updating submodule '\(path, privacy: .public)' in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["submodule", "update", "--init", "--", path])
        Logger.gitRepository.info("Submodule update complete in \(self.displayName, privacy: .public)")
    }

    // MARK: - Worktrees

    func removeWorktree(path: String, force: Bool) async throws {
        Logger.gitRepository.info(
            "Removing worktree '\(path, privacy: .public)' in \(self.displayName, privacy: .public)"
        )
        var args = ["worktree", "remove"]
        if force { args.append("--force") }
        args.append(path)
        try await shell.run(args)
        Logger.gitRepository.info("Worktree removed in \(self.displayName, privacy: .public)")
    }

    // MARK: - Blame

    func blame(file: String, revision: String?) async throws -> [BlameEntry] {
        var args = ["blame", "--porcelain"]
        if let revision { args.append(revision) }
        args += ["--", file]
        let result = try await shell.run(args)
        return BlameParser.parse(result.stdout)
    }

    // MARK: - Reflog

    func reflog(maxCount: Int) async throws -> [ReflogEntry] {
        let result = try await shell.run([
            "reflog",
            "--format=\(ReflogParser.formatString)",
            "-\(maxCount)"
        ])
        return ReflogParser.parse(result.stdout)
    }

    // MARK: - Pull Requests

    func pullRequests() async throws -> [PullRequestInfo] {
        Logger.gitRepository.info("Fetching pull requests in \(self.displayName, privacy: .public)")
        let result = try await ghRun([
            "pr", "list",
            "--json", "number,title,body,author,state,headRefName,baseRefName,createdAt,updatedAt,isDraft,labels,reviewRequests,statusCheckRollup",
            "--state", "all", "--limit", "100"
        ])
        let prs = try PRParser.parseList(result.stdout)
        Logger.gitRepository.info("Fetched \(prs.count, privacy: .public) pull requests in \(self.displayName, privacy: .public)")
        return prs
    }

    func pullRequestDetail(number: Int) async throws -> PullRequestInfo {
        Logger.gitRepository.info("Fetching PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        let result = try await ghRun([
            "pr", "view", "\(number)",
            "--json", "number,title,body,author,state,headRefName,baseRefName,createdAt,updatedAt,isDraft,labels,reviewRequests,statusCheckRollup"
        ])
        return try PRParser.parseSingle(result.stdout)
    }

    func pullRequestComments(number: Int) async throws -> [PRComment] {
        Logger.gitRepository.info("Fetching comments for PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        let result = try await ghRun([
            "pr", "view", "\(number)",
            "--json", "comments,reviews"
        ])
        return try PRParser.parseComments(result.stdout)
    }

    func checkoutPullRequest(number: Int) async throws {
        Logger.gitRepository.info("Checking out PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        try await ghRun(["pr", "checkout", "\(number)"])
        currentBranch   = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)
        Logger.gitRepository.info("Checked out PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
    }

    func closePullRequest(number: Int) async throws {
        Logger.gitRepository.info("Closing PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        try await ghRun(["pr", "close", "\(number)"])
        Logger.gitRepository.info("Closed PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
    }

    func mergePullRequest(number: Int) async throws {
        Logger.gitRepository.info("Merging PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
        try await ghRun(["pr", "merge", "\(number)", "--merge"])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        Logger.gitRepository.info("Merged PR #\(number, privacy: .public) in \(self.displayName, privacy: .public)")
    }

    // MARK: - Working Copy

    func commitIdentity() async -> CommitIdentity? {
        let name = await configValue("user.name")
        let email = await configValue("user.email")
        guard name != nil || email != nil else { return nil }
        return CommitIdentity(name: name ?? "Unknown", email: email ?? "")
    }

    func operationContext() async -> OperationContext? {
        guard let gitDir = await absoluteGitDir() else { return nil }
        let current = currentBranch?.name ?? "HEAD"
        switch repositoryState {
        case .merge:
            var incoming = Self.mergeSourceName(gitDir: gitDir)
            if incoming == nil { incoming = await revisionName("MERGE_HEAD") }
            return OperationContext(oursLabel: current, theirsLabel: incoming ?? "MERGE_HEAD")
        case .rebase, .rebaseInteractive:
            // During a rebase HEAD is the upstream being built on; the replayed branch is "theirs".
            let dir = ["rebase-merge", "rebase-apply"].map { gitDir.appendingPathComponent($0) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
            let headName = dir.flatMap { Self.readTrimmed($0.appendingPathComponent("head-name")) }
                .map { $0.replacingOccurrences(of: "refs/heads/", with: "") } ?? "HEAD"
            var ontoName = "upstream"
            if let onto = dir.flatMap({ Self.readTrimmed($0.appendingPathComponent("onto")) }) {
                ontoName = await revisionName(onto)
            }
            return OperationContext(oursLabel: ontoName, theirsLabel: headName)
        case .cherrypick:
            return OperationContext(oursLabel: current, theirsLabel: await revisionName("CHERRY_PICK_HEAD"))
        case .revert:
            return OperationContext(oursLabel: current, theirsLabel: "revert of " + (await revisionName("REVERT_HEAD")))
        case .normal, .bisect:
            return nil
        }
    }

    func continueOperation() async throws {
        let command: String
        switch repositoryState {
        case .merge: command = "merge"
        case .rebase, .rebaseInteractive: command = "rebase"
        case .cherrypick: command = "cherry-pick"
        case .revert: command = "revert"
        case .normal, .bisect: return
        }
        Logger.gitRepository.info("Continuing \(command, privacy: .public) in \(self.displayName, privacy: .public)")
        try await shell.run([command, "--continue"], environment: ["GIT_EDITOR": "true"])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)
    }

    func conflictVersions(path: String) async throws -> ConflictVersions {
        async let ours = shell.runAllowingFailure(["show", ":2:\(path)"])
        async let theirs = shell.runAllowingFailure(["show", ":3:\(path)"])
        let (o, t) = try await (ours, theirs)
        return ConflictVersions(ours: o.isSuccess ? o.stdout : nil, theirs: t.isSuccess ? t.stdout : nil)
    }

    func resolveConflict(path: String, side: ConflictSide) async throws {
        let stage = side == .ours ? ":2:" : ":3:"
        let exists = try await shell.runAllowingFailure(["cat-file", "-e", stage + path]).isSuccess
        if exists {
            try await shell.run(["checkout", side == .ours ? "--ours" : "--theirs", "--", path])
            try await shell.run(["add", "--", path])
        } else {
            // The chosen side deleted the file.
            try await shell.run(["rm", "--quiet", "--", path])
        }
    }

    private func configValue(_ key: String) async -> String? {
        guard let result = try? await shell.runAllowingFailure(["config", "--get", key]), result.isSuccess else { return nil }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func absoluteGitDir() async -> URL? {
        guard let result = try? await shell.run(["rev-parse", "--absolute-git-dir"]) else { return nil }
        return URL(fileURLWithPath: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A branch name for `rev` when one points at it, else its short SHA.
    private func revisionName(_ rev: String) async -> String {
        if let named = try? await shell.runAllowingFailure(["name-rev", "--name-only", "--no-undefined", "--exclude=tags/*", rev]),
           named.isSuccess {
            let name = named.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !name.contains("~"), !name.contains("^") {
                return name.replacingOccurrences(of: "remotes/", with: "")
            }
        }
        let short = try? await shell.run(["rev-parse", "--short", rev])
        return short?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? rev
    }

    /// Parses "Merge branch 'feature'" from MERGE_MSG, which names what the user merged.
    nonisolated private static func mergeSourceName(gitDir: URL) -> String? {
        guard let message = readTrimmed(gitDir.appendingPathComponent("MERGE_MSG")),
              let firstLine = message.split(separator: "\n").first,
              let open = firstLine.firstIndex(of: "'") else { return nil }
        let rest = firstLine[firstLine.index(after: open)...]
        guard let close = rest.firstIndex(of: "'") else { return nil }
        return String(rest[..<close])
    }

    nonisolated private static func readTrimmed(_ url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Private Helpers

    /// Run a `gh` CLI subcommand in the repository's working directory.
    ///
    /// Searches for `gh` in the same well-known locations used for `git`.
    /// Throws ``GitShellError/nonZeroExit`` when the process exits non-zero.
    @discardableResult
    private func ghRun(_ arguments: [String]) async throws -> ShellResult {
        let ghPath = GitRepository.resolveGhPath()
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ShellResult, Error>) in
            do {
                let process = Process()
                process.executableURL       = URL(fileURLWithPath: ghPath)
                process.arguments           = arguments
                process.currentDirectoryURL = path
                var env = ProcessInfo.processInfo.environment
                env["LANG"]    = "en_US.UTF-8"
                env["LC_ALL"]  = "en_US.UTF-8"
                process.environment = env

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError  = stderrPipe

                process.terminationHandler = { proc in
                    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout  = String(data: outData, encoding: .utf8) ?? ""
                    let stderr  = String(data: errData, encoding: .utf8) ?? ""
                    continuation.resume(returning: ShellResult(stdout: stdout, stderr: stderr, exitCode: proc.terminationStatus))
                }
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard result.isSuccess else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.gitRepository.warning(
                "gh \(arguments.first ?? "", privacy: .public) exited \(result.exitCode, privacy: .public): \(stderr, privacy: .public)"
            )
            throw GitShellError.nonZeroExit(
                command: "gh " + (arguments.first ?? ""),
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result
    }

    /// Resolve the path to the `gh` CLI executable.
    nonisolated private static func resolveGhPath() -> String {
        let candidates = [
            "/usr/local/bin/gh",
            "/opt/homebrew/bin/gh",
            "/usr/bin/gh"
        ]
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate) {
            return candidate
        }
        return "/usr/local/bin/gh"
    }

    /// Load the current branch from git, returning `nil` in detached-HEAD state.
    nonisolated private static func loadCurrentBranch(shell: GitShell) async throws -> BranchInfo? {
        // Check for detached HEAD first.
        let headResult = try await shell.runAllowingFailure(["symbolic-ref", "--quiet", "HEAD"])
        guard headResult.isSuccess else {
            return nil  // Detached HEAD.
        }

        let refname  = headResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let shortResult = try await shell.run(["rev-parse", "--abbrev-ref", "HEAD"])
        let shortName   = shortResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // Get the SHA.
        let shaResult = try await shell.run(["rev-parse", "HEAD"])
        let sha = shaResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        // Get upstream.
        let upstreamResult = try await shell.runAllowingFailure(
            ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"]
        )
        let upstream = upstreamResult.isSuccess
            ? upstreamResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil

        // Get ahead/behind.
        var ahead  = 0
        var behind = 0
        if let upstream {
            let abResult = try? await shell.run(
                ["rev-list", "--left-right", "--count", "HEAD...\(upstream)"]
            )
            if let abResult {
                let parts = abResult.stdout
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .components(separatedBy: "\t")
                ahead  = !parts.isEmpty ? (Int(parts[0]) ?? 0) : 0
                behind = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            }
        }

        return BranchInfo(
            id: refname,
            name: shortName,
            isLocal: true,
            isRemote: false,
            isHEAD: true,
            targetSHA: sha,
            remoteName: nil,
            upstream: upstream.map { "refs/remotes/\($0)" },
            ahead: ahead,
            behind: behind
        )
    }

    /// Determine the repository's current operation state.
    nonisolated private static func loadRepositoryState(path: URL) async -> RepositoryState {
        let gitDir = path.appendingPathComponent(".git")
        let fm     = FileManager.default

        // Check for in-progress operations via sentinel files/dirs.
        if fm.fileExists(atPath: gitDir.appendingPathComponent("MERGE_HEAD").path) {
            return .merge
        }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("rebase-merge").path) ||
           fm.fileExists(atPath: gitDir.appendingPathComponent("rebase-apply").path) {
            // Distinguish interactive from regular rebase.
            let interactivePath = gitDir.appendingPathComponent("rebase-merge/interactive").path
            return fm.fileExists(atPath: interactivePath) ? .rebaseInteractive : .rebase
        }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("REVERT_HEAD").path) {
            return .revert
        }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("CHERRY_PICK_HEAD").path) {
            return .cherrypick
        }
        if fm.fileExists(atPath: gitDir.appendingPathComponent("BISECT_LOG").path) {
            return .bisect
        }
        return .normal
    }

    /// Write `content` to a temporary executable shell script and return its URL.
    ///
    /// The caller is responsible for removing the file when done.
    private func writeTemporaryScript(_ content: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("grove-\(UUID().uuidString).sh")
        try content.write(to: url, atomically: true, encoding: .utf8)
        // Make the script executable.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755 as NSNumber],
            ofItemAtPath: url.path
        )
        return url
    }

    /// Wrap `string` in single quotes, escaping any embedded single quotes.
    ///
    /// Produces a POSIX shell literal safe for embedding in script bodies.
    nonisolated private func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Apply a patch string via `git apply`.
    private func applyPatch(_ patch: String, cached: Bool, reverse: Bool = false) async throws {
        var args = ["apply"]
        if cached { args.append("--cached") }
        if reverse { args.append("--reverse") }
        args += ["--whitespace=nowarn", "-"]

        do {
            try await shell.runWithInput(args, input: patch)
        } catch GitShellError.nonZeroExit(_, _, let stderr) {
            throw GitRepositoryError.applyPatchFailed(stderr)
        }
    }

    /// Fetch branches for a given ref pattern prefix.
    private func fetchBranches(refPattern: String) async throws -> [BranchInfo] {
        let result = try await shell.run([
            "for-each-ref",
            "--format=\(BranchParser.formatString)",
            refPattern
        ])
        return BranchParser.parse(result.stdout)
    }

    /// Parse `git remote -v` output into ``RemoteInfo`` values.
    nonisolated private func parseRemoteVerbose(_ output: String) -> [RemoteInfo] {
        var fetchURLs: [String: String] = [:]
        var pushURLs: [String: String] = [:]

        for line in output.components(separatedBy: "\n") {
            guard !line.isEmpty else { continue }
            // Format: `<name>\t<url> (fetch)` or `<name>\t<url> (push)`
            let parts = line.components(separatedBy: "\t")
            guard parts.count == 2 else { continue }
            let name    = parts[0]
            let urlPart = parts[1]

            if urlPart.hasSuffix(" (fetch)") {
                let url = String(urlPart.dropLast(" (fetch)".count))
                fetchURLs[name] = url
            } else if urlPart.hasSuffix(" (push)") {
                let url = String(urlPart.dropLast(" (push)".count))
                pushURLs[name] = url
            }
        }

        return fetchURLs.keys.sorted().map { name in
            let fetchURL = fetchURLs[name] ?? ""
            let pushURL  = pushURLs[name]
            return RemoteInfo(
                id: name,
                name: name,
                url: fetchURL,
                pushURL: pushURL == fetchURL ? nil : pushURL
            )
        }
    }

    /// Parse `git diff --name-status` output into a path→FileStatus map.
    nonisolated private func parseNameStatus(_ output: String) -> [String: FileStatus] {
        var result: [String: FileStatus] = [:]
        for line in output.components(separatedBy: "\n") {
            guard !line.isEmpty else { continue }
            let parts = line.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }
            let statusChar = parts[0].prefix(1)
            let path       = parts.last ?? parts[1]
            let status: FileStatus
            switch statusChar {
            case "A": status = .added
            case "D": status = .deleted
            case "R": status = .renamed
            case "C": status = .copied
            case "T": status = .typeChange
            default:  status = .modified
            }
            result[path] = status
        }
        return result
    }

    /// Parse `git for-each-ref` tag output into ``TagInfo`` values.
    nonisolated private func parseTagList(_ output: String) -> [TagInfo] {
        var result: [TagInfo] = []
        for line in output.components(separatedBy: "\n") {
            guard !line.isEmpty else { continue }
            let fields = line.components(separatedBy: "\0")
            guard fields.count >= 7 else { continue }

            let name        = fields[0]
            let sha         = fields[1]
            let objectType  = fields[2]
            let derefSHA    = fields[3]
            let subject     = fields[4]
            let taggerName  = fields[5].isEmpty ? nil : fields[5]
            let taggerDateStr = fields[6]

            let isAnnotated = objectType == "tag"
            let targetSHA   = isAnnotated && !derefSHA.isEmpty ? derefSHA : sha

            let taggerDate: Date?
            if !taggerDateStr.isEmpty {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
                taggerDate = formatter.date(from: taggerDateStr)
            } else {
                taggerDate = nil
            }

            result.append(TagInfo(
                id: name,
                name: name,
                targetSHA: targetSHA,
                isAnnotated: isAnnotated,
                message: isAnnotated ? subject : nil,
                taggerName: taggerName,
                taggerDate: taggerDate
            ))
        }
        return result
    }
}
