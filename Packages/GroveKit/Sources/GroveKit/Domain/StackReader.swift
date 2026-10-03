// Domain/StackReader.swift
// GroveKit
//
// Runs stack recognition after each refs read: gathers the graph, reflogs and patch-ids, and skips work when nothing moved.

import Foundation

/// Everything recognition depends on; equal keys give equal stacks.
private struct StackReadKey: Hashable {
    let trunk: String
    let tips: [String: String]
    let excluded: [String]
    let worktrees: [WorktreeInfo]
    let openPullRequests: [String: BranchPullRequest]
    let mergedPullRequests: [BranchPullRequest]
    let pullRequestsLoaded: Bool
}

@MainActor
final class StackReader {

    /// Above this many commits off trunk, recognition would cost more than it's worth.
    static let commitLimit = 20_000
    /// Commits patch-id'd per read; the rest wait for the next one.
    static let patchLimit = 4_000

    private(set) var recognition = StackRecognition()
    private(set) var trunk: String?
    private var lastKey: StackReadKey?
    /// Patch-ids never change for a commit, so they're kept across reads; "" marks a commit without one.
    private var patchIDs: [String: String] = [:]

    struct Snapshot {
        var localBranches: [BranchInfo]
        var remoteBranches: [BranchInfo]
        var remotes: [RemoteInfo]
        var worktrees: [WorktreeInfo]
        var openPullRequests: [String: BranchPullRequest]
        var mergedPullRequests: [BranchPullRequest]
        var pullRequestsLoaded: Bool
    }

    /// Recognizes stacks in `snapshot`; returns nil when nothing changed since the last read.
    func read(_ snapshot: Snapshot, repository: any GitRepositoryProtocol) async -> StackRecognition? {
        guard let trunk = await Self.trunk(snapshot, repository: repository) else {
            defer { recognition = StackRecognition(); lastKey = nil }
            return recognition.stacks.isEmpty && recognition.duplicates.isEmpty ? nil : StackRecognition()
        }
        let remote = Self.primaryRemote(snapshot.remotes)
        let excluded = ["refs/heads/\(trunk)", remote.map { "refs/remotes/\($0)/\(trunk)" }].compactMap { $0 }
            .filter { ref in (snapshot.localBranches + snapshot.remoteBranches).contains { $0.id == ref } }
        let branches = snapshot.localBranches.filter { $0.name != trunk }
        let key = StackReadKey(
            trunk: trunk, tips: Dictionary(branches.map { ($0.name, $0.targetSHA) }, uniquingKeysWith: { first, _ in first }),
            excluded: excluded.map { ref in (snapshot.localBranches + snapshot.remoteBranches).first { $0.id == ref }?.targetSHA ?? ref },
            worktrees: snapshot.worktrees, openPullRequests: snapshot.openPullRequests,
            mergedPullRequests: snapshot.mergedPullRequests, pullRequestsLoaded: snapshot.pullRequestsLoaded)
        guard key != lastKey else { return nil }

        guard !branches.isEmpty, !excluded.isEmpty,
              let graph = try? await repository.stackGraph(tips: branches.map(\.id), excluding: excluded),
              graph.order.count <= Self.commitLimit else {
            return publish(StackRecognition(), key: key, trunk: trunk)
        }
        let candidates = branches.filter { graph.parents[$0.targetSHA] != nil }.map(\.name)
        var input = StackRecognizerInput(
            trunk: trunk, branches: branches, graph: graph, formerTips: await repository.formerTips(of: candidates),
            openPullRequests: snapshot.openPullRequests, mergedPullRequests: snapshot.mergedPullRequests,
            pullRequestsLoaded: snapshot.pullRequestsLoaded, worktrees: snapshot.worktrees, currentPath: repository.path.path)
        input.patchIDs = knownPatchIDs(graph)
        var result = StackRecognizer.recognize(input)
        if result.wantsPatchIDs {
            let missing = graph.order.filter { patchIDs[$0] == nil }.prefix(Self.patchLimit)
            if !missing.isEmpty, let fresh = try? await repository.patchIDs(for: Array(missing)) {
                for sha in missing { patchIDs[sha] = fresh[sha] ?? "" }
                input.patchIDs = knownPatchIDs(graph)
                result = StackRecognizer.recognize(input)
            }
        }
        // Local trunk and its remote twin can each be ahead; the stack is behind whichever is further on.
        for index in result.stacks.indices {
            guard let base = result.trunkBases[result.stacks[index].id], !base.isEmpty else { continue }
            var ahead = 0
            for ref in excluded { ahead = max(ahead, await repository.commitCount(from: base, to: ref)) }
            result.stacks[index].trunkAhead = ahead
        }
        return publish(result, key: key, trunk: trunk)
    }

    private func publish(_ result: StackRecognition, key: StackReadKey, trunk: String) -> StackRecognition? {
        lastKey = key
        self.trunk = trunk
        guard result != recognition else { return nil }
        recognition = result
        return result
    }

    private func knownPatchIDs(_ graph: StackGraph) -> [String: String] {
        var known: [String: String] = [:]
        for sha in graph.order { if let id = patchIDs[sha], !id.isEmpty { known[sha] = id } }
        return known
    }

    /// The remote's default branch when git knows it, else the usual names, else HEAD's branch.
    static func trunk(_ snapshot: Snapshot, repository: any GitRepositoryProtocol) async -> String? {
        let names = Set(snapshot.localBranches.map(\.name))
        if let remote = primaryRemote(snapshot.remotes), let name = await repository.defaultBranch(of: remote),
           names.contains(name) || snapshot.remoteBranches.contains(where: { $0.name == "\(remote)/\(name)" }) {
            return name
        }
        guard !snapshot.localBranches.isEmpty else { return nil }
        return BranchesReviewViewModel.primaryBranchName(from: snapshot.localBranches)
    }

    static func primaryRemote(_ remotes: [RemoteInfo]) -> String? {
        remotes.first { $0.name == "origin" }?.name ?? remotes.first?.name
    }
}
