// Engine/GitRepository+Stash.swift
// GroveKit
//
// Stashes, submodules, worktrees, blame and reflog.

import Foundation
import os

extension GitRepository {

    // MARK: - Stash

    public func stashes() async throws -> [StashEntry] {
        let result = try await shell.run(
            ["stash", "list", "--format=\(StashParser.formatString)"]
        )
        return StashParser.parse(result.stdout)
    }

    public func stashCreate(message: String?, includeUntracked: Bool, paths: [String]? = nil) async throws {
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

    public func stashApply(index: Int, drop: Bool) async throws {
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
        repositoryState = await Self.loadRepositoryState(path: path, runner: shell.runner)
    }

    public func stashDrop(index: Int) async throws {
        try await shell.run(["stash", "drop", "stash@{\(index)}"])
    }

    @discardableResult
    public func saveSnapshot(message: String, includeUntracked: Bool) async throws -> Bool {
        Logger.gitRepository.info("Saving snapshot in \(self.displayName, privacy: .public)")
        var stash = try await shell.run(["stash", "create", message]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if includeUntracked, let untracked = try await untrackedSnapshotCommit() {
            stash = try await addUntracked(untracked, to: stash, message: message)
        }
        guard !stash.isEmpty else { return false }
        try await shell.run(["stash", "store", "-m", message, stash])
        return true
    }

    /// `stash create` has no `-u`, so the untracked files go in a root commit built from a throwaway index.
    private func untrackedSnapshotCommit() async throws -> String? {
        let listed = try await shell.run(["ls-files", "--others", "--exclude-standard", "-z"]).stdout
        let files = listed.split(separator: "\0").map(String.init)
        guard !files.isEmpty else { return nil }
        let index = scratchURL("snapshot")
        defer { discardScratch([index]) }
        let env = ["GIT_INDEX_FILE": index.path]
        try await shell.runWithInput(["update-index", "--add", "-z", "--stdin"], input: files.joined(separator: "\0"), environment: env)
        let tree = try await shell.run(["write-tree"], environment: env).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await shell.run(["commit-tree", tree, "-m", "untracked files"]).stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rebuilds the stash commit with the untracked commit as third parent, the layout `stash push -u` makes.
    private func addUntracked(_ untracked: String, to stash: String, message: String) async throws -> String {
        let trimmed: (ShellResult) -> String = { $0.stdout.trimmingCharacters(in: .whitespacesAndNewlines) }
        let head = trimmed(try await shell.run(["rev-parse", "HEAD"]))
        let tree: String
        let indexCommit: String
        if stash.isEmpty {
            // Only untracked files changed: the working tree and index both equal HEAD.
            tree = trimmed(try await shell.run(["rev-parse", "HEAD^{tree}"]))
            indexCommit = trimmed(try await shell.run(["commit-tree", tree, "-p", head, "-m", "index on snapshot"]))
        } else {
            tree = trimmed(try await shell.run(["rev-parse", "\(stash)^{tree}"]))
            indexCommit = trimmed(try await shell.run(["rev-parse", "\(stash)^2"]))
        }
        return trimmed(try await shell.run(["commit-tree", tree, "-p", head, "-p", indexCommit, "-p", untracked, "-m", message]))
    }

    // MARK: - Submodules

    public func updateSubmodule(path: String) async throws {
        Logger.gitRepository.info(
            "Updating submodule '\(path, privacy: .public)' in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["submodule", "update", "--init", "--", path])
        Logger.gitRepository.info("Submodule update complete in \(self.displayName, privacy: .public)")
    }

    public func submodules() async throws -> [SubmoduleInfo] {
        let gitmodules = path.appendingPathComponent(".gitmodules")
        guard let declared = await shell.runner.readString(at: gitmodules) else { return [] }
        let status = try await shell.runAllowingFailure(["submodule", "status"])
        return SubmoduleParser.parse(gitmodules: declared, status: status.isSuccess ? status.stdout : "")
    }

    // MARK: - Worktrees

    public func worktrees() async throws -> [WorktreeInfo] {
        WorktreeParser.parse(try await shell.run(["worktree", "list", "--porcelain"]).stdout)
    }

    public func pruneWorktrees() async throws {
        try await shell.run(["worktree", "prune"])
    }

    public func removeWorktree(path: String, force: Bool) async throws {
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

    public func blame(file: String, revision: String?) async throws -> [BlameEntry] {
        var args = ["blame", "--porcelain"]
        if let revision { args.append(revision) }
        args += ["--", file]
        let result = try await shell.run(args)
        return BlameParser.parse(result.stdout)
    }

    // MARK: - Reflog

    public func reflog(maxCount: Int) async throws -> [ReflogEntry] {
        let result = try await shell.run([
            "reflog",
            "--format=\(ReflogParser.formatString)",
            "-\(maxCount)"
        ])
        return ReflogParser.parse(result.stdout)
    }
}
