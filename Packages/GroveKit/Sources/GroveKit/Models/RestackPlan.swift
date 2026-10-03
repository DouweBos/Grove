// Models/RestackPlan.swift
// GroveKit
//
// A cascade of `rebase --onto` steps over a stack, saved as operation state so Continue and Abort survive a conflict.

import Foundation

/// Which layers a restack moves.
public nonisolated enum RestackMode: Hashable, Sendable {
    /// Layers that drifted from their parent, and everything above them.
    case drifted
    /// Every layer, the roots onto trunk's current tip: what Sync does after fetching.
    case ontoTrunk
    /// This layer and everything above it.
    case from(String)
    /// This layer (and its subtree) onto another branch, as in "Move onto…".
    case move(String, onto: String)
    /// Children of a merged parent onto trunk.
    case retarget(merged: String)
}

public nonisolated struct RestackPlan: Codable, Hashable, Sendable {

    struct Step: Codable, Hashable, Sendable {
        let branch: String
        /// Branch (or trunk ref) whose tip the layer goes onto, read when the step runs so it sees the parent's new tip.
        let onto: String
        /// Last commit that isn't the layer's own: `rebase --onto <onto> <oldBase> <branch>`.
        var oldBase: String
        let originalTip: String
        /// Another worktree the branch is checked out in, where the step runs instead.
        let worktreePath: String?
    }

    var stackName: String
    var steps: [Step]
    /// The step running or about to run.
    var next = 0
    /// Branch checked out before the cascade, checked out again after it.
    var originalBranch: String?
    /// Layers skipped because their worktree had changes or conflicted there.
    var skipped: [String] = []

    var isEmpty: Bool { steps.isEmpty }
    var current: Step? { steps.indices.contains(next) ? steps[next] : nil }

    /// "Restacking 3 of 5: 20-music".
    public var progressTitle: String {
        guard let current else { return "Restacking \(stackName)" }
        return "Restacking \(next + 1) of \(steps.count): \(current.branch)"
    }

    /// Steps in topological order, so a parent is always moved before its children.
    public static func make(_ stack: BranchStack, mode: RestackMode, trunkRef: String, headBranch: String?) -> RestackPlan {
        var moving: Set<String> = []
        var onto: [String: String] = [:]
        for layer in stack.layers {
            let parentMoves = layer.parent.map(moving.contains) ?? false
            let parentTarget = layer.parent.flatMap { stack.contains($0) ? $0 : nil } ?? trunkRef
            switch mode {
            case .drifted:
                if parentMoves || layer.health.contains(.needsRestack) { onto[layer.branch] = parentTarget }
            case .ontoTrunk:
                onto[layer.branch] = parentTarget
            case .from(let branch):
                if parentMoves || layer.branch == branch { onto[layer.branch] = parentTarget }
            case .move(let branch, let target):
                if layer.branch == branch { onto[layer.branch] = target } else if parentMoves { onto[layer.branch] = parentTarget }
            case .retarget(let merged):
                if layer.parent == merged { onto[layer.branch] = trunkRef } else if parentMoves { onto[layer.branch] = parentTarget }
            }
            if onto[layer.branch] != nil { moving.insert(layer.branch) }
        }
        let steps = stack.layers.compactMap { layer -> Step? in
            guard let target = onto[layer.branch] else { return nil }
            return Step(branch: layer.branch, onto: target, oldBase: layer.base, originalTip: layer.tipSHA,
                        worktreePath: layer.worktreePath)
        }
        return RestackPlan(stackName: stack.name, steps: steps, originalBranch: headBranch)
    }
}
