// GitKit/GitRepository+WorkingCopy.swift
// Grove
//
// Working copy identity, operation state and conflict resolution.

import Foundation
import os

extension GitRepository {

    // MARK: - Working Copy

    func commitIdentity() async -> CommitIdentity? {
        let name = await configValue("user.name")
        let email = await configValue("user.email")
        guard name != nil || email != nil else { return nil }
        return CommitIdentity(name: name ?? "Unknown", email: email ?? "")
    }

    func commitTemplate() async -> String? {
        guard let configured = await configValue("commit.template") else { return nil }
        let expanded = (configured as NSString).expandingTildeInPath
        let file = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : path.appendingPathComponent(expanded)
        return try? String(contentsOf: file, encoding: .utf8)
    }

    func operationContext() async -> OperationContext? {
        guard let gitDir = await absoluteGitDir() else { return nil }
        let current = currentBranch?.name ?? "HEAD"
        switch repositoryState {
        case .merge:
            var incoming = Self.mergeSourceName(gitDir: gitDir)
            if incoming == nil { incoming = await revisionName("MERGE_HEAD") }
            return OperationContext(oursLabel: current, theirsLabel: incoming ?? "MERGE_HEAD")
        case .rebase, .rebaseInteractive:
            // During a rebase HEAD is the upstream being built on; the replayed branch is "theirs".
            let dir = ["rebase-merge", "rebase-apply"].map { gitDir.appendingPathComponent($0) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
            let headName = dir.flatMap { Self.readTrimmed($0.appendingPathComponent("head-name")) }
                .map { $0.replacingOccurrences(of: "refs/heads/", with: "") } ?? "HEAD"
            var ontoName = "upstream"
            if let onto = dir.flatMap({ Self.readTrimmed($0.appendingPathComponent("onto")) }) {
                ontoName = await revisionName(onto)
            }
            return OperationContext(oursLabel: ontoName, theirsLabel: headName)
        case .cherrypick:
            return OperationContext(oursLabel: current, theirsLabel: await revisionName("CHERRY_PICK_HEAD"))
        case .revert:
            return OperationContext(oursLabel: current, theirsLabel: "revert of " + (await revisionName("REVERT_HEAD")))
        case .normal, .bisect:
            return nil
        }
    }

    func continueOperation() async throws {
        let command: String
        switch repositoryState {
        case .merge: command = "merge"
        case .rebase, .rebaseInteractive: command = "rebase"
        case .cherrypick: command = "cherry-pick"
        case .revert: command = "revert"
        case .normal, .bisect: return
        }
        Logger.gitRepository.info("Continuing \(command, privacy: .public) in \(self.displayName, privacy: .public)")
        try await shell.run([command, "--continue"], environment: ["GIT_EDITOR": "true"])
        currentBranch = try? await Self.loadCurrentBranch(shell: shell)
        repositoryState = await Self.loadRepositoryState(path: path)
    }

    func conflictVersions(path: String) async throws -> ConflictVersions {
        async let ours = shell.runAllowingFailure(["show", ":2:\(path)"])
        async let theirs = shell.runAllowingFailure(["show", ":3:\(path)"])
        let (o, t) = try await (ours, theirs)
        return ConflictVersions(ours: o.isSuccess ? o.stdout : nil, theirs: t.isSuccess ? t.stdout : nil)
    }

    func resolveConflict(path: String, side: ConflictSide) async throws {
        let stage = side == .ours ? ":2:" : ":3:"
        let exists = try await shell.runAllowingFailure(["cat-file", "-e", stage + path]).isSuccess
        if exists {
            try await shell.run(["checkout", side == .ours ? "--ours" : "--theirs", "--", path])
            try await shell.run(["add", "--", path])
        } else {
            // The chosen side deleted the file.
            try await shell.run(["rm", "--quiet", "--", path])
        }
    }

    func configValue(_ key: String) async -> String? {
        guard let result = try? await shell.runAllowingFailure(["config", "--get", key]), result.isSuccess else { return nil }
        let value = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func absoluteGitDir() async -> URL? {
        guard let result = try? await shell.run(["rev-parse", "--absolute-git-dir"]) else { return nil }
        return URL(fileURLWithPath: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// A branch name for `rev` when one points at it, else its short SHA.
    func revisionName(_ rev: String) async -> String {
        if let named = try? await shell.runAllowingFailure(["name-rev", "--name-only", "--no-undefined", "--exclude=tags/*", rev]),
           named.isSuccess {
            let name = named.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !name.contains("~"), !name.contains("^") {
                return name.replacingOccurrences(of: "remotes/", with: "")
            }
        }
        let short = try? await shell.run(["rev-parse", "--short", rev])
        return short?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? rev
    }

    /// Parses "Merge branch 'feature'" from MERGE_MSG, which names what the user merged.
    nonisolated private static func mergeSourceName(gitDir: URL) -> String? {
        guard let message = readTrimmed(gitDir.appendingPathComponent("MERGE_MSG")),
              let firstLine = message.split(separator: "\n").first,
              let open = firstLine.firstIndex(of: "'") else { return nil }
        let rest = firstLine[firstLine.index(after: open)...]
        guard let close = rest.firstIndex(of: "'") else { return nil }
        return String(rest[..<close])
    }

    nonisolated private static func readTrimmed(_ url: URL) -> String? {
        (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
