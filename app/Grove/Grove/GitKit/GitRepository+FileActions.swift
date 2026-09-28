// GitKit/GitRepository+FileActions.swift
// Grove
//
// Ignoring, untracking and moving working-copy files.

import Foundation
import os

extension GitRepository {

    func ignore(patterns: [String], localOnly: Bool) async throws {
        guard !patterns.isEmpty else { return }
        let file = localOnly ? try await gitPath("info/exclude") : path.appendingPathComponent(".gitignore")
        Logger.gitRepository.info("Ignoring \(patterns.count) patterns in \(file.lastPathComponent, privacy: .public)")
        try GitIgnoreFile.append(patterns, to: file)
    }

    func stopTracking(paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        try await shell.run(["rm", "--cached", "-r", "--quiet", "--"] + paths)
    }

    func moveFile(from source: String, to destination: String) async throws {
        let target = path.appendingPathComponent(destination)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let isTracked = try await shell.runAllowingFailure(["ls-files", "--error-unmatch", "--", source]).isSuccess
        if isTracked {
            try await shell.run(["mv", "--", source, destination])
        } else {
            try FileManager.default.moveItem(at: path.appendingPathComponent(source), to: target)
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
