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
}

extension StackGitOperations {
    func stackGraph(tips: [String], excluding: [String]) async throws -> StackGraph { StackGraph() }
    func patchIDs(for commits: [String]) async throws -> [String: String] { [:] }
    func formerTips(of branches: [String]) async -> [String: Set<String>] { [:] }
    func commitCount(from base: String, to revision: String) async -> Int { 0 }
    func forkPoint(parent: String, branch: String) async -> String? { nil }
}
