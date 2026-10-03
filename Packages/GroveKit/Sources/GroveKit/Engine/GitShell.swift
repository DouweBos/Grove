// Engine/GitShell.swift
// GroveKit
//
// Runs git commands in one working directory through a GitRunner, turning failures into GitShellError.
// All methods are `nonisolated` so they can be called from any actor context,
// including `nonisolated` helpers in GitRepository and background tasks.

import Foundation
import os

// MARK: - GitShellError

/// Errors produced by ``GitShell`` when a git process fails.
enum GitShellError: LocalizedError {
    /// The git process exited with a non-zero status code.
    case nonZeroExit(command: String, exitCode: Int32, stderr: String)
    /// The git executable could not be found on PATH.
    case gitNotFound
    /// The working directory URL is not a valid file-system path.
    case invalidWorkingDirectory(URL)
    /// The repository uses Git LFS but git-lfs isn't on PATH.
    case lfsNotInstalled

    /// git's and git-lfs's hook messages when a command needed git-lfs and couldn't run it.
    nonisolated static func isLFSMissing(_ stderr: String) -> Bool {
        stderr.contains("git-lfs: command not found") || stderr.contains("'lfs' is not a git command")
            || stderr.contains("'git-lfs' was not found on your path")
    }

    nonisolated static func failure(arguments: [String], result: ShellResult) -> GitShellError {
        if isLFSMissing(result.stderr) { return .lfsNotInstalled }
        return .nonZeroExit(command: arguments.first ?? "", exitCode: result.exitCode, stderr: result.stderr)
    }

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let command, _, let stderr):
            return GitErrorMessage.message(command: command, stderr: stderr)
        case .gitNotFound:
            return "Could not locate the git executable. Install Xcode Command Line Tools or Git."
        case .invalidWorkingDirectory(let url):
            return "The path '\(url.path)' is not a valid working directory."
        case .lfsNotInstalled:
            return LFSStatus.missingMessage
        }
    }
}

// MARK: - ShellResult

/// Output captured from a completed git process.
nonisolated struct ShellResult: Sendable {
    /// Standard output, decoded as UTF-8.
    let stdout: String
    /// Standard error, decoded as UTF-8.
    let stderr: String
    /// Process exit code (0 = success).
    let exitCode: Int32
    /// Raw standard output, for binary content such as images.
    var stdoutData = Data()

    /// Whether the process completed successfully.
    var isSuccess: Bool { exitCode == 0 }
}

// MARK: - GitShell

/// Runs `git` subcommands in one working directory, capturing stdout and stderr.
///
/// GitShell is `Sendable` (final class with only immutable stored properties).
///
/// ```swift
/// let shell = GitShell(workingDirectory: repoURL, runner: LocalGitRunner())
/// let result = try await shell.run(["log", "--oneline", "-10"])
/// print(result.stdout)
/// ```
final class GitShell: Sendable {

    // MARK: Properties

    /// Absolute URL of the repository working directory.
    nonisolated let workingDirectory: URL

    /// Where git runs and the worktree's files are read.
    nonisolated let runner: any GitRunner

    /// Variables added to every invocation of this shell.
    nonisolated private let extraEnvironment: [String: String]

    // MARK: Init

    /// - Parameters:
    ///   - workingDirectory: Absolute URL of the repository root.
    ///   - runner: Runs git and reaches the worktree's files.
    ///   - extraEnvironment: Additional environment variables injected into every process.
    nonisolated init(
        workingDirectory: URL,
        runner: any GitRunner,
        extraEnvironment: [String: String] = [:]
    ) {
        self.workingDirectory = workingDirectory
        self.runner = runner
        self.extraEnvironment = extraEnvironment
    }

    /// A shell on the same runner in another directory, e.g. a linked worktree.
    nonisolated func at(_ directory: URL) -> GitShell {
        GitShell(workingDirectory: directory, runner: runner, extraEnvironment: extraEnvironment)
    }

    // MARK: Public API

    /// Run a git subcommand and return captured output.
    ///
    /// - Parameters:
    ///   - arguments: The git arguments, e.g. `["log", "--oneline", "-10"]`.
    ///   - environment: Additional per-call environment overrides.
    /// - Returns: A ShellResult with stdout, stderr, and exit code.
    /// - Throws: GitShellError/nonZeroExit when exit code is non-zero.
    @discardableResult
    nonisolated func run(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) async throws -> ShellResult {
        let result = try await execute(arguments: arguments, environment: environment)
        guard result.isSuccess else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.gitShell.warning(
                "git \(arguments.first ?? "", privacy: .public) exited \(result.exitCode, privacy: .public): \(stderr, privacy: .public)"
            )
            throw GitShellError.failure(arguments: arguments, result: result)
        }
        return result
    }

    /// Runs a long git command (clone), streaming stderr to `onStderr`; cancelling the task stops git.
    nonisolated func runStreaming(_ arguments: [String], onStderr: @escaping @Sendable (String) -> Void) async throws {
        let result = try await runner.runStreaming(invocation(arguments, environment: [:]), onStderr: onStderr)
        try Task.checkCancellation()
        guard result.isSuccess else {
            throw GitShellError.nonZeroExit(command: arguments.first ?? "", exitCode: result.exitCode, stderr: result.stderr)
        }
    }

    /// Run a git subcommand, returning the result regardless of exit code.
    ///
    /// Use this when you need to inspect stderr or exit code without throwing.
    nonisolated func runAllowingFailure(
        _ arguments: [String],
        environment: [String: String] = [:]
    ) async throws -> ShellResult {
        try await execute(arguments: arguments, environment: environment)
    }

    /// Write `input` to stdin of a git command and return the output.
    ///
    /// Used for `git apply --cached` (hunk/line-level staging).
    @discardableResult
    nonisolated func runWithInput(
        _ arguments: [String],
        input: String,
        environment: [String: String] = [:]
    ) async throws -> ShellResult {
        let result = try await execute(arguments: arguments, environment: environment, input: Data(input.utf8))
        guard result.isSuccess else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.gitShell.warning(
                "git \(arguments.first ?? "", privacy: .public) (with input) exited \(result.exitCode, privacy: .public): \(stderr, privacy: .public)"
            )
            throw GitShellError.failure(arguments: arguments, result: result)
        }
        return result
    }

    // MARK: Private Execution

    nonisolated private func invocation(_ arguments: [String], environment: [String: String], input: Data? = nil) -> GitInvocation {
        GitInvocation(arguments: arguments, workingDirectory: workingDirectory, shellEnvironment: extraEnvironment,
                      environment: environment, input: input)
    }

    nonisolated private func execute(
        arguments: [String],
        environment: [String: String],
        input: Data? = nil
    ) async throws -> ShellResult {
        let commandLine = arguments.joined(separator: " ")
        Logger.gitShell.debug("Running: git \(commandLine, privacy: .public)")
        let start = Date()

        let result = try await runner.run(invocation(arguments, environment: environment, input: input))

        let elapsed = Date().timeIntervalSince(start)
        Logger.gitShell.debug(
            "Finished: git \(commandLine, privacy: .public) [\(String(format: "%.3f", elapsed), privacy: .public)s, exit \(result.exitCode, privacy: .public)]"
        )
        if !result.stderr.isEmpty && result.exitCode != 0 {
            Logger.gitShell.error(
                "stderr: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)"
            )
        }
        return result
    }
}
