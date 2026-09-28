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
    case rebaseStopped

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
        case .rebaseStopped:
            return "The rebase stopped on a conflict. Resolve it in Changes, then continue the rebase."
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

    let shell: GitShell

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

        let branch = currentBranch?.name ?? "detached HEAD"
        Logger.gitRepository.info(
            "Repository opened: \(path.lastPathComponent, privacy: .public) on \(branch, privacy: .public) [state: \(self.repositoryState.logDescription, privacy: .public)]"
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
}
