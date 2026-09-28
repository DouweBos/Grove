// GitKit/GitRepository+Stash.swift
// Grove
//
// Stashes, submodules, worktrees, blame and reflog.

import Foundation
import os

extension GitRepository {

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

    // MARK: - Submodules

    func updateSubmodule(path: String) async throws {
        Logger.gitRepository.info(
            "Updating submodule '\(path, privacy: .public)' in \(self.displayName, privacy: .public)"
        )
        try await shell.run(["submodule", "update", "--init", "--", path])
        Logger.gitRepository.info("Submodule update complete in \(self.displayName, privacy: .public)")
    }

    func submodules() async throws -> [SubmoduleInfo] {
        let gitmodules = path.appendingPathComponent(".gitmodules")
        guard let declared = try? String(contentsOf: gitmodules, encoding: .utf8) else { return [] }
        let status = try await shell.runAllowingFailure(["submodule", "status"])
        return SubmoduleParser.parse(gitmodules: declared, status: status.isSuccess ? status.stdout : "")
    }

    // MARK: - Worktrees

    func worktrees() async throws -> [WorktreeInfo] {
        WorktreeParser.parse(try await shell.run(["worktree", "list", "--porcelain"]).stdout)
    }

    func pruneWorktrees() async throws {
        try await shell.run(["worktree", "prune"])
    }

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
}
