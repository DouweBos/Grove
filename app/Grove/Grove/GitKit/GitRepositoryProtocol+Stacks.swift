// GitKit/GitRepositoryProtocol+Stacks.swift
// Grove
//
// What stack recognition and restacking need from git; part of GitRepositoryProtocol.

import Foundation

@MainActor
protocol StackGitOperations: AnyObject {
    /// Commits reachable from `tips` but none of `excluding`, with their parents, children first.
    func stackGraph(tips: [String], excluding: [String]) async throws -> StackGraph
    /// `git patch-id --stable` of each of `commits`; merges and empty commits have none.
    func patchIDs(for commits: [String]) async throws -> [String: String]
    /// SHAs each branch was moved to, read from its reflog, leaving out where it was created.
    func formerTips(of branches: [String]) async -> [String: Set<String>]
    /// Commits in `revision` that `base` lacks.
    func commitCount(from base: String, to revision: String) async -> Int
    /// `git merge-base --fork-point <parent> <branch>`: where `branch` left `parent`, by `parent`'s reflog.
    func forkPoint(parent: String, branch: String) async -> String?
    /// Lines added and removed between two commits.
    func diffStats(from base: String, to revision: String) async throws -> DiffStats
    /// Runs `plan`, saving it as operation state; throws ``RestackError/stopped(_:)`` when a layer conflicts.
    func restack(_ plan: RestackPlan) async throws
    /// Continues the rebase that stopped the restack, then the rest of the cascade; a plain operation without one.
    func continueRestack() async throws
    /// Aborts the stopped rebase and resets every layer already moved.
    func abortRestack() async throws
    /// The restack that stopped on a conflict, if any.
    func pendingRestack() async -> RestackPlan?
}

extension StackGitOperations {
    func stackGraph(tips: [String], excluding: [String]) async throws -> StackGraph { StackGraph() }
    func patchIDs(for commits: [String]) async throws -> [String: String] { [:] }
    func formerTips(of branches: [String]) async -> [String: Set<String>] { [:] }
    func commitCount(from base: String, to revision: String) async -> Int { 0 }
    func forkPoint(parent: String, branch: String) async -> String? { nil }
    func diffStats(from base: String, to revision: String) async throws -> DiffStats { DiffStats(additions: 0, deletions: 0) }
    func restack(_ plan: RestackPlan) async throws {}
    func continueRestack() async throws {}
    func abortRestack() async throws {}
    func pendingRestack() async -> RestackPlan? { nil }
}
