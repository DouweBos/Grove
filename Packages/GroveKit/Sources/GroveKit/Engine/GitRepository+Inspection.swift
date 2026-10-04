// Engine/GitRepository+Inspection.swift
// GroveKit
//
// Stash/PR diffs, file contents, branch merge state and local config.

import Foundation

extension GitRepository {

    private var inspectionShell: GitShell { shell }

    // MARK: Stash

    public func stashDiff(index: Int) async throws -> [FileDiff] {
        let ref = "stash@{\(index)}"
        let shell = inspectionShell
        let patch = try await shell.run(["stash", "show", "-p", "-U3", "--include-untracked", ref])
        let names = try await shell.run(["stash", "show", "--name-status", "--include-untracked", ref])
        return DiffParser.fileDiffs(patch: patch.stdout, nameStatus: names.stdout)
    }

    // MARK: Files

    public func fileContents(path file: String, revision: String?) async throws -> String {
        guard let revision else {
            let data = try await shell.runner.readFile(at: path.appendingPathComponent(file))
            guard let text = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
            return text
        }
        return try await inspectionShell.run(["show", "\(revision):\(file)"]).stdout
    }

    public func fileData(path file: String, at revision: FileRevision) async throws -> Data {
        switch revision {
        case .workingTree:
            return try await shell.runner.readFile(at: path.appendingPathComponent(file))
        case .index:
            return await smudgedIfLFSPointer(try await inspectionShell.run(["show", ":\(file)"]).stdoutData, path: file)
        case .conflictStage(let stage):
            return await smudgedIfLFSPointer(try await inspectionShell.run(["show", ":\(stage):\(file)"]).stdoutData, path: file)
        case .commit(let rev):
            return await smudgedIfLFSPointer(try await inspectionShell.run(["show", "\(rev):\(file)"]).stdoutData, path: file)
        }
    }

    // MARK: Branch Review

    public func mergedBranches(into base: String) async throws -> Set<String> {
        let result = try await inspectionShell.run(["branch", "--merged", base, "--format=%(refname:short)"])
        return Set(result.stdout.split(separator: "\n").map(String.init))
    }

    public func aheadBehind(branch: String, base: String) async throws -> (ahead: Int, behind: Int) {
        let result = try await inspectionShell.run(["rev-list", "--left-right", "--count", "\(branch)...\(base)"])
        let parts = result.stdout.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
        guard parts.count == 2 else { return (0, 0) }
        return (parts[0], parts[1])
    }

    public func compareBranches(base: String, compare: String) async throws -> BranchComparison {
        let shell = inspectionShell
        let range = "\(base)...\(compare)"
        let log = try await shell.run(["log", "--left-right", "--cherry-mark", "--date-order", "-1000",
                                       "--format=%m%x00\(LogParser.formatString)", range])
        let numstat = try await shell.run(["diff", "--numstat", "--no-renames", range])
        var comparison = BranchComparison(files: Self.parseNumstat(numstat.stdout))
        for record in log.stdout.components(separatedBy: "\u{01}") {
            let trimmed = record.trimmingCharacters(in: .newlines)
            guard let mark = trimmed.first, let commit = LogParser.parse(String(trimmed.dropFirst(2))).first else { continue }
            switch mark {
            case "<": comparison.onlyInBase.append(commit)
            case ">": comparison.onlyInCompare.append(commit)
            default: comparison.equivalentCount += 1
            }
        }
        // `=` marks both copies of a patch, so pairs are roughly half.
        comparison.equivalentCount = (comparison.equivalentCount + 1) / 2
        return comparison
    }

    nonisolated static func parseNumstat(_ output: String) -> [ChangedFileStat] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 2).map(String.init)
            guard parts.count == 3 else { return nil }
            return ChangedFileStat(path: parts[2], additions: Int(parts[0]), deletions: Int(parts[1]))
        }
    }

    // MARK: Local Config

    public func localConfigValue(_ key: String) async throws -> String? {
        // Exit code 1 just means the key is unset.
        let result = try await inspectionShell.runAllowingFailure(["config", "--local", "--get", key])
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isSuccess && !value.isEmpty ? value : nil
    }

    public func setLocalConfigValue(_ key: String, to value: String?) async throws {
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

    public func setRemoteURL(_ url: String, forRemote name: String) async throws {
        try await inspectionShell.run(["remote", "set-url", name, url])
    }

    public func addRemote(name: String, url: String) async throws {
        try await inspectionShell.run(["remote", "add", name, url])
    }

    public func removeRemote(name: String) async throws {
        try await inspectionShell.run(["remote", "remove", name])
    }
}
