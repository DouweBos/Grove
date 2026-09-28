// GitKit/GitRepository+Commits.swift
// Grove
//
// Commits, reset and clean.

import Foundation
import os

extension GitRepository {

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
        try await log(maxCount: maxCount, skip: skip, revisions: branch.map { [$0] } ?? [])
    }

    func log(maxCount: Int, skip: Int, revisions: [String]) async throws -> [CommitInfo] {
        let args = ["log", "--format=\(LogParser.formatString)", "--author-date-order", "-\(maxCount)", "--skip=\(skip)"]
            + revisions + ["--"]
        let result = try await shell.run(args)
        return LogParser.parse(result.stdout)
    }

    func commits(in revision: String, notIn base: String) async throws -> Set<String> {
        let result = try await shell.run(["rev-list", "\(base)..\(revision)", "--"])
        return Set(result.stdout.split(separator: "\n").map(String.init))
    }

    func isAncestor(_ commit: String, of descendant: String) async -> Bool {
        let result = try? await shell.runAllowingFailure(["merge-base", "--is-ancestor", commit, descendant])
        return result?.isSuccess ?? false
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
            ["log", "--format=\(LogParser.verifiedFormatString)", "-1", sha]
        )
        let commits = LogParser.parse(result.stdout)
        guard let commit = commits.first else {
            throw GitRepositoryError.commitNotFound(sha)
        }
        return commit
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
}
