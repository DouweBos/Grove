// Engine/GitRepository+FileActions.swift
// GroveKit
//
// Ignoring, untracking and moving working-copy files.

import Foundation
import os

extension GitRepository {

    public func ignore(patterns: [String], localOnly: Bool) async throws {
        guard !patterns.isEmpty else { return }
        let file = localOnly ? try await gitPath("info/exclude") : path.appendingPathComponent(".gitignore")
        Logger.gitRepository.info("Ignoring \(patterns.count) patterns in \(file.lastPathComponent, privacy: .public)")
        try await GitIgnoreFile.append(patterns, to: file, runner: shell.runner)
    }

    public func stopTracking(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await shell.run(["rm", "--cached", "-r", "--quiet", "--"] + paths)
    }

    public func moveFile(from source: String, to destination: String) async throws {
        let target = path.appendingPathComponent(destination)
        try await shell.runner.createParentDirectory(of: target)
        let isTracked = try await shell.runAllowingFailure(["ls-files", "--error-unmatch", "--", source]).isSuccess
        if isTracked {
            try await shell.run(["mv", "--", source, destination])
        } else {
            try await shell.runner.moveItem(at: path.appendingPathComponent(source), to: target)
        }
    }

    public func restoreFile(_ file: String, from revision: String, revisionPath: String) async throws {
        Logger.gitRepository.info("Restoring \(file, privacy: .public) from \(revision, privacy: .public)")
        if revisionPath == file {
            // restore applies checkout filters (LFS, eol), which a raw `git show` would skip.
            try await shell.run(["restore", "--source=\(revision)", "--worktree", "--", file])
        } else {
            let data = try await shell.run(["show", "\(revision):\(revisionPath)"]).stdoutData
            let target = path.appendingPathComponent(file)
            try await shell.runner.writeFile(data, to: target, executable: false)
        }
    }

    /// `git rev-parse --git-path`, which resolves linked worktrees to the shared git dir where needed.
    func gitPath(_ name: String) async throws -> URL {
        let output = try await shell.run(["rev-parse", "--git-path", name]).stdout
        let resolved = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = resolved.hasPrefix("/") ? URL(fileURLWithPath: resolved) : path.appendingPathComponent(resolved)
        return url.standardizedFileURL
    }
}
