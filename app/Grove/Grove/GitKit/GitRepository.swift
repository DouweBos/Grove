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
    case tagNotFound(String)
    case cannotDeleteCurrentBranch
    case remoteOperationFailed(String)
    case stashIndexOutOfRange(Int)
    case applyPatchFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAGitRepository(let url):
            return "'\(url.path)' is not a Git repository."
        case .invalidCommitMessage:
            return "A commit message is required."
        case .branchNotFound(let name):
            return "Branch '\(name)' not found."
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
        let result = try await shell.run(["status", "--porcelain=v2", "-uall"])
        return StatusParser.parse(result.stdout)
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
        let patch = DiffParser.buildReversePatch(from: hunk, filePath: file)
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
        // Restore working-tree changes for tracked files.
        let result = try await shell.runAllowingFailure(
            ["restore", "--worktree", "--"] + paths
        )
        if !result.isSuccess {
            // Fallback for older git.
            try await shell.run(["checkout", "--"] + paths)
        }
    }

    func discardHunk(_ hunk: HunkData, in file: String) async throws {
        // Apply a reverse patch to the working tree (no --cached).
        let patch = DiffParser.buildReversePatch(from: hunk, filePath: file)
        try await applyPatch(patch, cached: false, reverse: false)
    }

    // MARK: - Diff

    func diff(for entry: StatusEntry, staged: Bool) async throws -> DiffResult {
        let args: [String]
        if staged {
            // diff HEAD → index (what would be committed)
            args = ["diff", "--cached", "-U3", "--", entry.path]
        } else {
            // diff index → working tree (unstaged changes)
            args = ["diff", "-U3", "--", entry.path]
        }
        let result = try await shell.run(args)
        return DiffParser.parseSingleFile(result.stdout) ?? DiffResult(
            filePath: entry.path,
            oldPath: nil,
            isBinary: false,
            hunks: [],
            stats: DiffStats(additions: 0, deletions: 0)
        )
    }

    func diffForCommit(_ sha: String) async throws -> [FileDiff] {
        // Show the diff introduced by this commit.
        let diffResult = try await shell.run(
            ["diff", "-U3", "--diff-filter=ACDMRT", "\(sha)^!", "--"]
        )
        let diffs = DiffParser.parse(diffResult.stdout)

        // Also get the status for each file.
        let statusResult = try await shell.run(
            ["diff", "--name-status", "--diff-filter=ACDMRT", "\(sha)^!", "--"]
        )
        let statusMap = parseNameStatus(statusResult.stdout)

        return diffs.map { diff in
            let status = statusMap[diff.filePath] ?? .modified
            return FileDiff(
                path:   diff.filePath,
                status: status,
                diff:   diff,
                stats:  diff.stats
            )
        }
    }

    // MARK: - Commits

    @discardableResult
    func commit(message: String, body: String?, amend: Bool) async throws -> CommitInfo {
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
        try await shell.run(args)

        // Return the newly created commit.
        let commits = try await log(maxCount: 1, skip: 0, branch: nil)
        guard let commit = commits.first else {
            throw GitRepositoryError.invalidCommitMessage
        }

        Logger.gitRepository.info(
            "\(operation, privacy: .public) succeeded: \(commit.shortSHA, privacy: .public) in \(self.displayName, privacy: .public)"
        )

        // Refresh branch state.
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        return commit
    }

    func log(maxCount: Int, skip: Int, branch: String?) async throws -> [CommitInfo] {
        var args = [
            "log",
            "--format=\(LogParser.formatString)",
            "-\(maxCount)",
            "--skip=\(skip)",
        ]
        if let branch {
            args.append(branch)
        }
        let result = try await shell.run(args)
        return LogParser.parse(result.stdout)
    }

    func commitDetail(_ sha: String) async throws -> CommitInfo {
        let result = try await shell.run(
            ["log", "--format=\(LogParser.formatString)", "-1", sha]
        )
        let commits = LogParser.parse(result.stdout)
        guard let commit = commits.first else {
            throw GitRepositoryError.branchNotFound(sha)
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

    func push(remote: String?, force: Bool, forceLease: Bool, progress: (@Sendable (Double) -> Void)?) async throws {
        let forceDescription = forceLease ? " --force-with-lease" : (force ? " --force" : "")
        Logger.gitRepository.info(
            "Pushing\(forceDescription, privacy: .public) to \(remote ?? "default", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        var args = ["push"]
        if forceLease {
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

    // MARK: - Stash

    func stashes() async throws -> [StashEntry] {
        let result = try await shell.run(
            ["stash", "list", "--format=\(StashParser.formatString)"]
        )
        return StashParser.parse(result.stdout)
    }

    func stashCreate(message: String?, includeUntracked: Bool) async throws {
        Logger.gitRepository.info(
            "Creating stash\(message.map { " '\($0)'" } ?? "", privacy: .public) in \(self.displayName, privacy: .public)"
        )
        var args = ["stash", "push"]
        if includeUntracked { args.append("--include-untracked") }
        if let message {
            args += ["-m", message]
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
    func createTag(name: String, at sha: String?, message: String?) async throws -> TagInfo {
        var args: [String]
        if let message {
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

    // MARK: - Private Helpers

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
                ahead  = parts.count > 0 ? (Int(parts[0]) ?? 0) : 0
                behind = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
            }
        }

        return BranchInfo(
            id:         refname,
            name:       shortName,
            isLocal:    true,
            isRemote:   false,
            isHEAD:     true,
            targetSHA:  sha,
            remoteName: nil,
            upstream:   upstream.map { "refs/remotes/\($0)" },
            ahead:      ahead,
            behind:     behind
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

    /// Apply a patch string via `git apply`.
    private func applyPatch(_ patch: String, cached: Bool, reverse: Bool = false) async throws {
        var args = ["apply"]
        if cached  { args.append("--cached") }
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
        var pushURLs:  [String: String] = [:]

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
                id:      name,
                name:    name,
                url:     fetchURL,
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
                id:          name,
                name:        name,
                targetSHA:   targetSHA,
                isAnnotated: isAnnotated,
                message:     isAnnotated ? subject : nil,
                taggerName:  taggerName,
                taggerDate:  taggerDate
            ))
        }
        return result
    }
}

