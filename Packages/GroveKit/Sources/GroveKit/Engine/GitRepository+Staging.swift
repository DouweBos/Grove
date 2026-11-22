// Engine/GitRepository+Staging.swift
// GroveKit
//
// Staging, unstaging and diffs.

import Foundation
import os

extension GitRepository {

    // MARK: - Staging

    public func stage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await shell.run(["add", "--"] + paths)
    }

    public func unstage(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        // Use `git restore --staged` (git 2.23+); fallback: `git reset HEAD --`
        let result = try await shell.runAllowingFailure(["restore", "--staged", "--"] + paths)
        if !result.isSuccess {
            try await shell.run(["reset", "HEAD", "--"] + paths)
        }
    }

    public func stageAll() async throws {
        try await shell.run(["add", "-A"])
    }

    public func unstageAll() async throws {
        try await shell.run(["reset", "HEAD"])
    }

    public func discardChanges(paths: [String]) async throws {
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

    // MARK: - Diff

    public func diff(for entry: StatusEntry, staged: Bool, ignoreWhitespace: Bool = false) async throws -> DiffResult {
        let untracked = !staged && entry.workdirStatus == .untracked
        let output = try await workingDiff(entry.path, staged: staged, untracked: untracked, ignoreWhitespace: ignoreWhitespace)
        return Self.section(for: entry.path, in: DiffParser.parse(output.stdout)) ?? DiffResult(
            filePath: entry.path,
            oldPath: nil,
            isBinary: false,
            hunks: [],
            stats: DiffStats(additions: 0, deletions: 0)
        )
    }

    public func diffForCommit(_ sha: String) async throws -> [FileDiff] {
        try await diffForCommit(sha, paths: [])
    }

    public func diffForCommit(_ sha: String, path: String) async throws -> [FileDiff] {
        try await diffForCommit(sha, paths: [path])
    }

    private func diffForCommit(_ sha: String, paths: [String]) async throws -> [FileDiff] {
        // `show` handles root commits; merges diff against their first parent.
        let base = ["show", "--format=", "-M", "--diff-merges=first-parent", "--no-ext-diff", "--no-color"]
        let diffResult = try await shell.run(base + ["-U3", sha, "--"] + paths)
        // Without the final newline the parser doesn't read a phantom empty context line.
        let output = diffResult.stdout.hasSuffix("\n") ? String(diffResult.stdout.dropLast()) : diffResult.stdout
        let diffs = DiffParser.parse(output)
        let statusResult = try await shell.run(base + ["--name-status", sha, "--"] + paths)
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

    public func diff(from: String, to: String) async throws -> [FileDiff] {
        let base = ["diff", "-M", "--no-ext-diff", "--no-color"]
        let patch = try await shell.run(base + ["-U3", from, to, "--"]).stdout
        let names = try await shell.run(base + ["--name-status", from, to, "--"]).stdout
        return DiffParser.fileDiffs(patch: patch, nameStatus: names)
    }

    public func filesInCommit(_ sha: String) async throws -> [String] {
        let result = try await shell.run(["ls-tree", "-r", "--name-only", "--full-tree", sha])
        return result.stdout.split(separator: "\n").map { GitPathQuoting.unquote(String($0)) }
    }
}
