// GitKit/GitRepository+Staging.swift
// Grove
//
// Staging, unstaging and diffs.

import Foundation
import os

extension GitRepository {

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
        try await diffForCommit(sha, paths: [])
    }

    func diffForCommit(_ sha: String, path: String) async throws -> [FileDiff] {
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

    func filesInCommit(_ sha: String) async throws -> [String] {
        let result = try await shell.run(["ls-tree", "-r", "--name-only", "--full-tree", sha])
        return result.stdout.split(separator: "\n").map(String.init)
    }
}
