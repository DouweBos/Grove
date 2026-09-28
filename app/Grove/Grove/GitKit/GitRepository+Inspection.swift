// GitKit/GitRepository+Inspection.swift
// Grove
//
// Stash/PR diffs, file contents, branch merge state and local config.

import Foundation

extension GitRepository {

    private var inspectionShell: GitShell { shell }

    // MARK: Stash

    func stashDiff(index: Int) async throws -> [FileDiff] {
        let ref = "stash@{\(index)}"
        let shell = inspectionShell
        let patch = try await shell.run(["stash", "show", "-p", "-U3", "--include-untracked", ref])
        let names = try await shell.run(["stash", "show", "--name-status", "--include-untracked", ref])
        return Self.fileDiffs(patch: patch.stdout, nameStatus: names.stdout)
    }

    // MARK: Files

    func fileContents(path file: String, revision: String?) async throws -> String {
        guard let revision else {
            return try String(contentsOf: path.appendingPathComponent(file), encoding: .utf8)
        }
        return try await inspectionShell.run(["show", "\(revision):\(file)"]).stdout
    }

    // MARK: Branch Review

    func mergedBranches(into base: String) async throws -> Set<String> {
        let result = try await inspectionShell.run(["branch", "--merged", base, "--format=%(refname:short)"])
        return Set(result.stdout.split(separator: "\n").map(String.init))
    }

    func aheadBehind(branch: String, base: String) async throws -> (ahead: Int, behind: Int) {
        let result = try await inspectionShell.run(["rev-list", "--left-right", "--count", "\(branch)...\(base)"])
        let parts = result.stdout.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        guard parts.count == 2 else { return (0, 0) }
        return (parts[0], parts[1])
    }

    // MARK: Local Config

    func localConfigValue(_ key: String) async throws -> String? {
        // Exit code 1 just means the key is unset.
        let result = try await inspectionShell.runAllowingFailure(["config", "--local", "--get", key])
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isSuccess && !value.isEmpty ? value : nil
    }

    func setLocalConfigValue(_ key: String, to value: String?) async throws {
        let shell = inspectionShell
        if let value, !value.isEmpty {
            try await shell.run(["config", "--local", key, value])
        } else {
            // Exit code 5 means the key was already unset.
            let result = try await shell.runAllowingFailure(["config", "--local", "--unset", key])
            guard result.isSuccess || result.exitCode == 5 else {
                throw GitShellError.nonZeroExit(command: "config", exitCode: result.exitCode, stderr: result.stderr)
            }
        }
    }

    func setRemoteURL(_ url: String, forRemote name: String) async throws {
        try await inspectionShell.run(["remote", "set-url", name, url])
    }

    // MARK: Pull Requests

    func pullRequestDiff(number: Int) async throws -> [FileDiff] {
        let patch = try await GitHubCLI.run(["pr", "diff", "\(number)"], in: path)
        let names = try await GitHubCLI.run(["pr", "diff", "\(number)", "--name-only"], in: path)
        let diffs = DiffParser.parse(patch)
        let listed = Set(names.split(separator: "\n").map(String.init))
        return diffs
            .filter { listed.isEmpty || listed.contains($0.filePath) }
            .map { FileDiff(path: $0.filePath, status: Self.inferStatus($0), diff: $0, stats: $0.stats) }
    }

    func pullRequestCommits(number: Int) async throws -> [CommitInfo] {
        let json = try await GitHubCLI.run(["pr", "view", "\(number)", "--json", "commits"], in: path)
        return GitHubCLI.parseCommits(json)
    }

    // MARK: Helpers

    nonisolated static func fileDiffs(patch: String, nameStatus: String) -> [FileDiff] {
        var statuses: [String: FileStatus] = [:]
        for line in nameStatus.split(separator: "\n") {
            let parts = line.split(separator: "\t").map(String.init)
            guard parts.count >= 2, let code = parts[0].first,
                  let status = FileStatus(rawValue: String(code)) else { continue }
            statuses[parts[parts.count - 1]] = status
        }
        return DiffParser.parse(patch).map { diff in
            FileDiff(path: diff.filePath, status: statuses[diff.filePath] ?? inferStatus(diff),
                     diff: diff, stats: diff.stats)
        }
    }

    nonisolated static func inferStatus(_ diff: DiffResult) -> FileStatus {
        if diff.oldPath != nil { return .renamed }
        if let hunk = diff.hunks.first, diff.hunks.count == 1 {
            if hunk.oldStart == 0 && hunk.oldCount == 0 { return .added }
            if hunk.newStart == 0 && hunk.newCount == 0 { return .deleted }
        }
        return .modified
    }
}
