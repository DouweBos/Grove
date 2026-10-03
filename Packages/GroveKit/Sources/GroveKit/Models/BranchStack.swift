// Models/BranchStack.swift
// GroveKit
//
// Branches stacked on each other, as recognized from the commit graph, reflogs, patch-ids and pull requests.

import Foundation

/// Something about a layer that asks for an action.
nonisolated enum LayerHealth: String, Hashable, Sendable, CaseIterable {
    /// The parent moved on (amended, rebased, restacked) without this layer.
    case needsRestack
    /// The parent's pull request merged; this layer should move onto trunk and retarget its PR.
    case parentMerged
    /// Commits the upstream lacks, or no upstream at all.
    case unpushed
    /// Both this branch and its upstream have commits the other lacks, as after a restack.
    case diverged
    /// Pull requests loaded and none is open for this branch.
    case noPR

    var symbol: String {
        switch self {
        case .needsRestack: "arrow.triangle.2.circlepath"
        case .parentMerged: "arrow.merge"
        case .unpushed: "arrow.up"
        case .diverged: "arrow.up.arrow.down"
        case .noPR: "arrow.triangle.pull"
        }
    }

    var title: String {
        switch self {
        case .needsRestack: "Needs restack"
        case .parentMerged: "Parent merged"
        case .unpushed: "Unpushed"
        case .diverged: "Diverged from upstream"
        case .noPR: "No pull request"
        }
    }
}

/// One branch of a stack.
nonisolated struct StackLayer: Identifiable, Hashable, Sendable {
    var id: String { branch }
    let branch: String
    let tipSHA: String
    /// The branch below, or nil when the layer sits on trunk.
    let parent: String?
    /// Last commit that belongs to the parent rather than this layer: `rebase --onto <parent> <base> <branch>`.
    var base: String
    /// This layer's own commits along the first-parent chain, newest first.
    let commits: [String]
    var health: Set<LayerHealth>
    let pullRequest: BranchPullRequest?
    /// The merged pull request of the parent, when `health` has `.parentMerged`.
    let mergedParent: BranchPullRequest?
    let ahead: Int
    let behind: Int
    let hasUpstream: Bool
    let isHEAD: Bool
    /// A linked worktree the branch is checked out in, if not the one Grove has open.
    let worktreePath: String?
    /// Distance from trunk: roots are 0.
    let depth: Int
}

/// A tree of layers on one trunk branch; splits show as siblings.
nonisolated struct BranchStack: Identifiable, Hashable, Sendable {
    /// The root layer's branch, which stays stable while layers above come and go.
    var id: String { layers.first?.branch ?? name }
    let name: String
    let trunk: String
    /// Topological order: every parent comes before its children, siblings by name.
    let layers: [StackLayer]
    /// Commits on trunk since the root's base, filled in once counted.
    var trunkAhead: Int = 0

    var roots: [StackLayer] { layers.filter { $0.parent == nil || layer($0.parent!) == nil } }

    func layer(_ branch: String) -> StackLayer? { layers.first { $0.branch == branch } }

    func children(of branch: String) -> [StackLayer] { layers.filter { $0.parent == branch } }

    func contains(_ branch: String) -> Bool { layer(branch) != nil }

    /// Layers from `branch` up through all its descendants, in topological order.
    func subtree(from branch: String) -> [StackLayer] {
        var included: Set<String> = [branch]
        return layers.filter { layer in
            if layer.branch == branch { return true }
            guard let parent = layer.parent, included.contains(parent) else { return false }
            included.insert(layer.branch)
            return true
        }
    }

    var needsAttention: Bool { layers.contains { !$0.health.isDisjoint(with: [.needsRestack, .parentMerged]) } }
}

/// A branch whose patches all exist on another branch: an older copy, flagged rather than stacked.
nonisolated struct DuplicateBranch: Hashable, Sendable {
    let branch: String
    let duplicateOf: String
}
