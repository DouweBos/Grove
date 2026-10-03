// Engine/GitRepository+BranchReview.swift
// GroveKit
//
// Batched branch tips and ahead/behind counts for Branches Review.

import Foundation
import os

extension GitRepository {

    nonisolated static let branchTipFormat =
        "%(refname:short)%00%(objectname)%00%(committerdate:iso-strict)%00%(authorname)%00%(contents:subject)"

    /// Fallback `rev-list` processes in flight at once when `%(ahead-behind)` is unavailable.
    nonisolated static let aheadBehindConcurrency = 8

    func branchTips() async throws -> [BranchTip] {
        let result = try await shell.run(["for-each-ref", "refs/heads", "--format=\(Self.branchTipFormat)"])
        return Self.parseBranchTips(result.stdout)
    }

    func aheadBehind(branches: [String], base: String) async throws -> [String: AheadBehind] {
        guard !branches.isEmpty else { return [:] }
        let shell = shell
        if let version = await GitVersion.current(shell: shell), version >= GitVersion(major: 2, minor: 41) {
            // One commit walk for every branch; patterns keep it to the branches that need counting.
            let patterns = branches.map { "refs/heads/\($0)" }
            let result = try await shell.run(["for-each-ref", "--format=%(refname:short)%00%(ahead-behind:refs/heads/\(base))"]
                                             + patterns)
            return Self.parseAheadBehind(result.stdout)
        }
        return try await Self.aheadBehindViaRevList(branches: branches, base: base, shell: shell)
    }

    nonisolated static func aheadBehindViaRevList(branches: [String], base: String,
                                                  shell: GitShell) async throws -> [String: AheadBehind] {
        try await withThrowingTaskGroup(of: (String, AheadBehind?).self) { group in
            var pending = branches[...]
            func addNext() {
                guard let branch = pending.popFirst() else { return }
                group.addTask {
                    let result = try await shell.run(["rev-list", "--left-right", "--count",
                                                      "refs/heads/\(branch)...refs/heads/\(base)"])
                    let parts = result.stdout.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }
                    return (branch, parts.count == 2 ? AheadBehind(ahead: parts[0], behind: parts[1]) : nil)
                }
            }
            for _ in 0..<aheadBehindConcurrency { addNext() }
            var counts: [String: AheadBehind] = [:]
            for try await (branch, value) in group {
                counts[branch] = value
                addNext()
            }
            return counts
        }
    }

    // MARK: Parsing

    nonisolated static func parseBranchTips(_ output: String) -> [BranchTip] {
        output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 5 else { return nil }
            return BranchTip(name: fields[0], sha: fields[1], committerDate: GitDate.parse(fields[2]),
                             authorName: fields[3], summary: fields[4])
        }
    }

    /// Parses `name\0<ahead> <behind>` lines.
    nonisolated static func parseAheadBehind(_ output: String) -> [String: AheadBehind] {
        var counts: [String: AheadBehind] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\0", omittingEmptySubsequences: false)
            guard fields.count == 2 else { continue }
            let numbers = fields[1].split(separator: " ").compactMap { Int($0) }
            guard numbers.count == 2 else { continue }
            counts[String(fields[0])] = AheadBehind(ahead: numbers[0], behind: numbers[1])
        }
        return counts
    }
}

/// Installed git version, read once per executable since features like `%(ahead-behind)` depend on it.
nonisolated struct GitVersion: Comparable, Sendable {
    let major: Int
    let minor: Int

    static func < (lhs: GitVersion, rhs: GitVersion) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }

    /// Parses `git version 2.39.5 (Apple Git-154)`.
    static func parse(_ output: String) -> GitVersion? {
        guard let token = output.split(separator: " ").first(where: { $0.first?.isNumber == true }) else { return nil }
        let parts = token.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return GitVersion(major: parts[0], minor: parts[1])
    }

    private static let cache = OSAllocatedUnfairLock<GitVersion?>(initialState: nil)

    static func current(shell: GitShell) async -> GitVersion? {
        if let cached = cache.withLock({ $0 }) { return cached }
        guard let output = try? await shell.run(["version"]).stdout, let version = parse(output) else { return nil }
        cache.withLock { $0 = version }
        return version
    }
}
