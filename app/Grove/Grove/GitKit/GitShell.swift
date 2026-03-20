// GitKit/GitShell.swift
// Grove
//
// Async wrapper around Foundation.Process for running git CLI commands.
// All shell invocations go through this type, keeping Process management
// in one place and making it easy to replace later.
//
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

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let command, let code, let stderr):
            let detail = stderr.isEmpty
                ? "(no stderr)"
                : stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "git \(command) exited with code \(code): \(detail)"
        case .gitNotFound:
            return "Could not locate the git executable. Install Xcode Command Line Tools or Git."
        case .invalidWorkingDirectory(let url):
            return "The path '\(url.path)' is not a valid working directory."
        }
    }
}

// MARK: - ShellResult

/// Output captured from a completed git process.
struct ShellResult: Sendable {
    /// Standard output, decoded as UTF-8.
    let stdout: String
    /// Standard error, decoded as UTF-8.
    let stderr: String
    /// Process exit code (0 = success).
    let exitCode: Int32

    /// Whether the process completed successfully.
    var isSuccess: Bool { exitCode == 0 }
}

// MARK: - GitShell

/// Runs `git` subcommands as child processes, capturing stdout and stderr.
///
/// All methods are `nonisolated` so they can be called from any actor context
/// without switching to the main actor. ``GitShell`` itself is `Sendable`
/// (final class with only immutable stored properties after init).
///
/// ```swift
/// let shell = GitShell(workingDirectory: repoURL)
/// let result = try await shell.run(["log", "--oneline", "-10"])
/// print(result.stdout)
/// ```
final class GitShell: Sendable {

    // MARK: Properties

    /// Absolute URL of the repository working directory.
    nonisolated let workingDirectory: URL

    /// Path to the git executable. Resolved once at init.
    nonisolated private let gitPath: String

    /// Base environment variables merged into every process launch.
    nonisolated private let baseEnvironment: [String: String]

    // MARK: Init

    /// Creates a new shell runner for `workingDirectory`.
    ///
    /// - Parameters:
    ///   - workingDirectory: Absolute URL of the repository root.
    ///   - gitPath: Optional override for the git executable path.
    ///     Defaults to resolving `git` from well-known locations.
    ///   - extraEnvironment: Additional environment variables injected into
    ///     every process. Merged on top of the inherited environment.
    nonisolated init(
        workingDirectory: URL,
        gitPath: String? = nil,
        extraEnvironment: [String: String] = [:]
    ) {
        self.workingDirectory = workingDirectory
        self.gitPath = gitPath ?? GitShell.resolveGitPath()
        var env = ProcessInfo.processInfo.environment
        // Ensure consistent output encoding and locale-independent parsing.
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        // Disable pager output so we always get plain text.
        env["GIT_PAGER"] = "cat"
        env["PAGER"] = "cat"
        // Disable interactive prompts (prevents hanging in CI or when no TTY).
        env["GIT_TERMINAL_PROMPT"] = "0"
        for (key, value) in extraEnvironment {
            env[key] = value
        }
        self.baseEnvironment = env
    }

    // MARK: Public API

    /// Run a git subcommand and return captured output.
    ///
    /// - Parameters:
    ///   - arguments: The git arguments, e.g. `["log", "--oneline", "-10"]`.
    ///   - environment: Additional per-call environment overrides.
    /// - Returns: A ``ShellResult`` with stdout, stderr, and exit code.
    /// - Throws: ``GitShellError/nonZeroExit`` when exit code is non-zero.
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
            throw GitShellError.nonZeroExit(
                command: arguments.first ?? "",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result
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
        let result = try await executeWithInput(
            arguments: arguments,
            input: input,
            environment: environment
        )
        guard result.isSuccess else {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.gitShell.warning(
                "git \(arguments.first ?? "", privacy: .public) (with input) exited \(result.exitCode, privacy: .public): \(stderr, privacy: .public)"
            )
            throw GitShellError.nonZeroExit(
                command: arguments.first ?? "",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result
    }

    // MARK: Private Execution

    nonisolated private func execute(
        arguments: [String],
        environment: [String: String]
    ) async throws -> ShellResult {
        let commandLine = arguments.joined(separator: " ")
        Logger.gitShell.debug("Running: git \(commandLine, privacy: .public)")
        let start = Date()

        return try await withCheckedThrowingContinuation { continuation in
            do {
                let process = try buildProcess(arguments: arguments, environment: environment)
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError  = stderrPipe

                process.terminationHandler = { proc in
                    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout  = String(data: outData, encoding: .utf8) ?? ""
                    let stderr  = String(data: errData, encoding: .utf8) ?? ""
                    let elapsed = Date().timeIntervalSince(start)
                    Logger.gitShell.debug(
                        "Finished: git \(commandLine, privacy: .public) [\(String(format: "%.3f", elapsed), privacy: .public)s, exit \(proc.terminationStatus, privacy: .public)]"
                    )
                    if !stderr.isEmpty && proc.terminationStatus != 0 {
                        Logger.gitShell.error(
                            "stderr: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)"
                        )
                    }
                    continuation.resume(returning: ShellResult(
                        stdout:   stdout,
                        stderr:   stderr,
                        exitCode: proc.terminationStatus
                    ))
                }

                try process.run()
            } catch {
                Logger.gitShell.error("Failed to launch git \(commandLine, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continuation.resume(throwing: error)
            }
        }
    }

    nonisolated private func executeWithInput(
        arguments: [String],
        input: String,
        environment: [String: String]
    ) async throws -> ShellResult {
        let commandLine = arguments.joined(separator: " ")
        Logger.gitShell.debug("Running (with input): git \(commandLine, privacy: .public)")
        let start = Date()

        return try await withCheckedThrowingContinuation { continuation in
            do {
                let process = try buildProcess(arguments: arguments, environment: environment)
                let stdinPipe  = Pipe()
                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardInput  = stdinPipe
                process.standardOutput = stdoutPipe
                process.standardError  = stderrPipe

                process.terminationHandler = { proc in
                    let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                    let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stdout  = String(data: outData, encoding: .utf8) ?? ""
                    let stderr  = String(data: errData, encoding: .utf8) ?? ""
                    let elapsed = Date().timeIntervalSince(start)
                    Logger.gitShell.debug(
                        "Finished: git \(commandLine, privacy: .public) [\(String(format: "%.3f", elapsed), privacy: .public)s, exit \(proc.terminationStatus, privacy: .public)]"
                    )
                    if !stderr.isEmpty && proc.terminationStatus != 0 {
                        Logger.gitShell.error(
                            "stderr: \(stderr.trimmingCharacters(in: .whitespacesAndNewlines), privacy: .public)"
                        )
                    }
                    continuation.resume(returning: ShellResult(
                        stdout:   stdout,
                        stderr:   stderr,
                        exitCode: proc.terminationStatus
                    ))
                }

                try process.run()

                if let data = input.data(using: .utf8) {
                    stdinPipe.fileHandleForWriting.write(data)
                }
                stdinPipe.fileHandleForWriting.closeFile()
            } catch {
                Logger.gitShell.error("Failed to launch git \(commandLine, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continuation.resume(throwing: error)
            }
        }
    }

    nonisolated private func buildProcess(
        arguments: [String],
        environment: [String: String]
    ) throws -> Process {
        var env = baseEnvironment
        for (key, value) in environment {
            env[key] = value
        }

        let process = Process()
        process.executableURL       = URL(fileURLWithPath: gitPath)
        process.arguments           = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment         = env
        return process
    }

    // MARK: Git Path Resolution

    nonisolated private static func resolveGitPath() -> String {
        let candidates = [
            "/usr/bin/git",
            "/usr/local/bin/git",
            "/opt/homebrew/bin/git",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        return "/usr/bin/git"
    }
}
