// Models/BranchStack.swift
// GroveKit
//
// Branches stacked on each other, as recognized from the commit graph, reflogs, patch-ids and pull requests.

import Foundation

/// Something about a layer that asks for an action.
public nonisolated enum LayerHealth: String, Hashable, Sendable, CaseIterable {
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

    public var symbol: String {
        switch self {
        case .needsRestack: "arrow.triangle.2.circlepath"
        case .parentMerged: "arrow.merge"
        case .unpushed: "arrow.up"
        case .diverged: "arrow.up.arrow.down"
        case .noPR: "arrow.triangle.pull"
        }
    }

    public var title: String {
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
public nonisolated struct StackLayer: Identifiable, Hashable, Sendable {
    public var id: String { branch }
    public let branch: String
    let tipSHA: String
    /// The branch below, or nil when the layer sits on trunk.
    public let parent: String?
    /// Last commit that belongs to the parent rather than this layer: `rebase --onto <parent> <base> <branch>`.
    var base: String
    /// This layer's own commits along the first-parent chain, newest first.
    public let commits: [String]
    public var health: Set<LayerHealth>
    public let pullRequest: BranchPullRequest?
    /// The merged pull request of the parent, when `health` has `.parentMerged`.
    let mergedParent: BranchPullRequest?
    public let ahead: Int
    public let behind: Int
    let hasUpstream: Bool
    public let isHEAD: Bool
    /// A linked worktree the branch is checked out in, if not the one the app has open.
    public let worktreePath: String?
    /// Distance from trunk: roots are 0.
    public let depth: Int

    public init(branch: String, tipSHA: String, parent: String? = nil, base: String, commits: [String], health: Set<LayerHealth>, pullRequest: BranchPullRequest? = nil, mergedParent: BranchPullRequest? = nil, ahead: Int, behind: Int, hasUpstream: Bool, isHEAD: Bool, worktreePath: String? = nil, depth: Int) {
        self.branch = branch
        self.tipSHA = tipSHA
        self.parent = parent
        self.base = base
        self.commits = commits
        self.health = health
        self.pullRequest = pullRequest
        self.mergedParent = mergedParent
        self.ahead = ahead
        self.behind = behind
        self.hasUpstream = hasUpstream
        self.isHEAD = isHEAD
        self.worktreePath = worktreePath
        self.depth = depth
    }
}

/// A tree of layers on one trunk branch; splits show as siblings.
public nonisolated struct BranchStack: Identifiable, Hashable, Sendable {
    /// The root layer's branch, which stays stable while layers above come and go.
    public var id: String { layers.first?.branch ?? name }
    public let name: String
    public let trunk: String
    /// Topological order: every parent comes before its children, siblings by name.
    public let layers: [StackLayer]
    /// Commits on trunk since the root's base, filled in once counted.
    public var trunkAhead: Int = 0

    public init(name: String, trunk: String, layers: [StackLayer], trunkAhead: Int = 0) {
        self.name = name
        self.trunk = trunk
        self.layers = layers
        self.trunkAhead = trunkAhead
    }

    public var roots: [StackLayer] { layers.filter { $0.parent == nil || layer($0.parent!) == nil } }

    public func layer(_ branch: String) -> StackLayer? { layers.first { $0.branch == branch } }

    public func children(of branch: String) -> [StackLayer] { layers.filter { $0.parent == branch } }

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

    public var needsAttention: Bool { layers.contains { !$0.health.isDisjoint(with: [.needsRestack, .parentMerged]) } }
}

/// A branch whose patches all exist on another branch: an older copy, flagged rather than stacked.
nonisolated struct DuplicateBranch: Hashable, Sendable {
    public let branch: String
    let duplicateOf: String
}
