// Engine/GitRepository+Stacks.swift
// GroveKit
//
// The git reads stack recognition runs on: one rev-list for the graph, reflog files, and patch-ids.

import Foundation
import os

extension GitRepository {

    public func stackGraph(tips: [String], excluding: [String]) async throws -> StackGraph {
        guard !tips.isEmpty else { return StackGraph() }
        let args = ["rev-list", "--parents", "--topo-order"] + tips + ["--not"] + excluding + ["--"]
        return StackGraph.parse(try await shell.run(args).stdout)
    }

    public func patchIDs(for commits: [String]) async throws -> [String: String] {
        guard !commits.isEmpty else { return [:] }
        let diffs = try await shell.runWithInput(["diff-tree", "--stdin", "-p", "--no-color", "--pretty=format:commit %H"],
                                                 input: commits.joined(separator: "\n") + "\n")
        let ids = try await shell.runWithInput(["patch-id", "--stable"], input: diffs.stdout)
        return Self.parsePatchIDs(ids.stdout)
    }

    /// `<patch-id> <commit>` lines → [commit: patch-id].
    nonisolated static func parsePatchIDs(_ output: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ")
            if fields.count == 2 { result[String(fields[1])] = String(fields[0]) }
        }
        return result
    }

    /// Reads `logs/refs/heads/<branch>` directly: one file per branch beats one `git reflog` per branch.
    public func formerTips(of branches: [String]) async -> [String: Set<String>] {
        guard let common = try? await shell.run(["rev-parse", "--path-format=absolute", "--git-common-dir"]) else { return [:] }
        let logs = URL(fileURLWithPath: common.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            .appendingPathComponent("logs/refs/heads")
        let runner = shell.runner
        return await Task.detached {
            var result: [String: Set<String>] = [:]
            for branch in branches {
                guard let text = await runner.readString(at: logs.appendingPathComponent(branch)) else { continue }
                result[branch] = Self.parseReflogTips(text)
            }
            return result
        }.value
    }

    /// The new SHA of every `<old> <new> <ident>\t<message>` line except the one creating the branch,
    /// which marks where it started rather than where it was.
    nonisolated static func parseReflogTips(_ text: String) -> Set<String> {
        var tips: Set<String> = []
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 2)
            guard fields.count == 3, fields[0].contains(where: { $0 != "0" }), fields[1].count >= 40 else { continue }
            tips.insert(String(fields[1]))
        }
        return tips
    }

    public func commitCount(from base: String, to revision: String) async -> Int {
        guard let result = try? await shell.runAllowingFailure(["rev-list", "--count", "\(base)..\(revision)", "--"]),
              result.isSuccess else { return 0 }
        return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    public func forkPoint(parent: String, branch: String) async -> String? {
        guard let result = try? await shell.runAllowingFailure(["merge-base", "--fork-point", parent, branch]),
              result.isSuccess else { return nil }
        let sha = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return sha.isEmpty ? nil : sha
    }

    public func diffStats(from base: String, to revision: String) async throws -> DiffStats {
        Self.parseShortStat(try await shell.run(["diff", "--shortstat", base, revision, "--"]).stdout)
    }

    /// ` 3 files changed, 140 insertions(+), 12 deletions(-)` → +140 −12.
    nonisolated static func parseShortStat(_ output: String) -> DiffStats {
        func count(_ word: String) -> Int {
            guard let range = output.range(of: word) else { return 0 }
            let digits = output[..<range.lowerBound].reversed().drop(while: { $0 == " " }).prefix(while: \.isNumber)
            return Int(String(digits.reversed())) ?? 0
        }
        return DiffStats(additions: count("insertion"), deletions: count("deletion"))
    }
}
