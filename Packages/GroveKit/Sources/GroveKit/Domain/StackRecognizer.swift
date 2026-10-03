// Domain/StackRecognizer.swift
// GroveKit
//
// Recognizes stacked branches from the repository alone: the commit graph, reflogs, patch-ids and pull requests.
// Nothing Grove records is read, so stacks made with plain `git checkout -b` show up the same way.

import Foundation

/// Commits reachable from the candidate tips but not from trunk, from one `git rev-list --parents --topo-order`.
public nonisolated struct StackGraph: Hashable, Sendable {
    /// Children before parents.
    var order: [String] = []
    /// Parent SHAs of each commit in `order`; parents on trunk are listed but not in `order`.
    var parents: [String: [String]] = [:]

    /// `<sha> <parent> <parent>…` lines.
    static func parse(_ output: String) -> StackGraph {
        var graph = StackGraph()
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ").map(String.init)
            guard let sha = fields.first else { continue }
            graph.order.append(sha)
            graph.parents[sha] = Array(fields.dropFirst())
        }
        return graph
    }
}

/// Everything recognition reads; each part comes from git or the host in one pass.
nonisolated struct StackRecognizerInput: Sendable {
    var trunk: String
    /// Local branches other than trunk; those with no commits off trunk are ignored.
    public var branches: [BranchInfo]
    var graph: StackGraph
    /// SHAs each branch pointed at before its current tip, from its reflog; creation entries are left out.
    var formerTips: [String: Set<String>] = [:]
    /// `git patch-id --stable` by commit; empty until the background pass has run.
    var patchIDs: [String: String] = [:]
    var openPullRequests: [String: BranchPullRequest] = [:]
    var mergedPullRequests: [BranchPullRequest] = []
    /// False when the host couldn't be reached, so a missing PR means nothing.
    var pullRequestsLoaded = false
    var worktrees: [WorktreeInfo] = []
    /// The worktree Grove has open; a layer checked out anywhere else notes that worktree.
    var currentPath: String = ""
}

nonisolated struct StackRecognition: Hashable, Sendable {
    public var stacks: [BranchStack] = []
    var duplicates: [DuplicateBranch] = []
    /// The trunk commit each stack's root grew from, keyed by stack id, for counting what trunk gained since.
    var trunkBases: [String: String] = [:]
    /// A layer on trunk has commits without patch-ids, so a patch-id pass might still find its parent.
    var wantsPatchIDs = false
}

nonisolated enum StackRecognizer {

    /// How a layer's parent was found, strongest first.
    enum Evidence { case graph, reflog, diverged, patchID, pullRequestBase, mergedPullRequest, none }

    struct Resolution {
        var parent: String?
        var base: String
        var commits: [String]
        var evidence: Evidence
        var mergedParent: BranchPullRequest?
    }

    static func recognize(_ input: StackRecognizerInput) -> StackRecognition {
        let dag = DAG(input)
        guard dag.candidates.count > 0 else { return StackRecognition() }
        var resolutions: [String: Resolution] = [:]
        var duplicates: [DuplicateBranch] = []
        var wantsPatchIDs = false
        for name in dag.candidates {
            var resolution = dag.walk(name)
            if resolution.parent == nil {
                switch dag.patchParent(name, own: resolution.commits) {
                case .parent(let parent, let base, let own):
                    resolution = Resolution(parent: parent, base: base, commits: own, evidence: .patchID)
                case .duplicate(let of):
                    duplicates.append(DuplicateBranch(branch: name, duplicateOf: of))
                    continue
                case .none:
                    wantsPatchIDs = wantsPatchIDs || (dag.candidates.count > 1 && resolution.commits.contains { input.patchIDs[$0] == nil })
                    resolution = dag.fallbackParent(name, resolution)
                }
            }
            resolutions[name] = resolution
        }
        let duplicateNames = Set(duplicates.map(\.branch))
        for name in duplicateNames { resolutions[name] = nil }
        for (name, resolution) in resolutions where resolution.parent.map(duplicateNames.contains) == true {
            resolutions[name]?.parent = nil
            resolutions[name]?.evidence = .none
        }
        breakCycles(&resolutions)
        let assembled = assemble(resolutions, dag: dag, input: input)
        return StackRecognition(stacks: assembled.stacks, duplicates: duplicates.sorted { $0.branch < $1.branch },
                                trunkBases: assembled.trunkBases, wantsPatchIDs: wantsPatchIDs)
    }

    private static func breakCycles(_ resolutions: inout [String: Resolution]) {
        for name in resolutions.keys.sorted() {
            var seen: Set<String> = [name]
            var current = resolutions[name]?.parent
            while let next = current, resolutions[next] != nil {
                if seen.contains(next) {
                    resolutions[name]?.parent = nil
                    resolutions[name]?.evidence = .none
                    break
                }
                seen.insert(next)
                current = resolutions[next]?.parent
            }
        }
    }

    // MARK: - Assembly

    private static func assemble(_ resolutions: [String: Resolution], dag: DAG,
                                 input: StackRecognizerInput) -> (stacks: [BranchStack], trunkBases: [String: String]) {
        let branches = Dictionary(input.branches.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let children = Dictionary(grouping: resolutions.keys.filter { resolutions[$0]?.parent.flatMap { resolutions[$0] } != nil }) {
            resolutions[$0]!.parent!
        }
        let roots = resolutions.keys.filter { name in resolutions[name]?.parent.flatMap { resolutions[$0] } == nil }.sorted()
        var stacks: [BranchStack] = []
        var trunkBases: [String: String] = [:]
        for root in roots {
            var layers: [StackLayer] = []
            func visit(_ name: String, depth: Int) {
                guard let resolution = resolutions[name], let branch = branches[name] else { return }
                layers.append(layer(branch, resolution, depth: depth, resolutions: resolutions, input: input))
                for child in (children[name] ?? []).sorted() { visit(child, depth: depth + 1) }
            }
            visit(root, depth: 0)
            // A lone branch counts when its parent merged, unless it has nothing of its own to move.
            guard layers.count > 1 || layers.contains(where: { $0.health.contains(.parentMerged) && !$0.commits.isEmpty }) else { continue }
            let stack = BranchStack(name: stackName(layers.map(\.branch)), trunk: input.trunk, layers: layers)
            stacks.append(stack)
            if let rootResolution = resolutions[root] { trunkBases[stack.id] = dag.trunkStop(from: rootResolution.base) }
        }
        return (stacks, trunkBases)
    }

    private static func layer(_ branch: BranchInfo, _ resolution: Resolution, depth: Int,
                              resolutions: [String: Resolution], input: StackRecognizerInput) -> StackLayer {
        var health: Set<LayerHealth> = []
        if [.reflog, .diverged, .patchID, .pullRequestBase].contains(resolution.evidence) { health.insert(.needsRestack) }
        let open = input.openPullRequests[branch.name]
        var mergedParent = resolution.mergedParent
        if mergedParent == nil, let parent = resolution.parent, input.openPullRequests[parent] == nil {
            let parentTip = input.branches.first { $0.name == parent }?.targetSHA
            mergedParent = input.mergedPullRequests.first { $0.headBranch == parent && (parentTip.map($0.headMatches) ?? true) }
        }
        // A PR still based on a branch that merged needs retargeting even when the commits are already fine.
        if mergedParent == nil, let base = open?.baseBranch, !base.isEmpty, base != input.trunk, input.openPullRequests[base] == nil {
            mergedParent = input.mergedPullRequests.first { $0.headBranch == base }
        }
        if mergedParent != nil { health.insert(.parentMerged) }
        if !branch.hasUpstreamRef || (branch.ahead > 0 && branch.behind == 0) { health.insert(.unpushed) }
        if branch.ahead > 0 && branch.behind > 0 { health.insert(.diverged) }
        let merged = input.mergedPullRequests.first { $0.headBranch == branch.name && $0.headMatches(branch.targetSHA) }
        if input.pullRequestsLoaded, open == nil, merged == nil { health.insert(.noPR) }
        let worktree = input.worktrees.first { $0.branch == branch.name && canonical($0.path) != canonical(input.currentPath) }
        return StackLayer(branch: branch.name, tipSHA: branch.targetSHA, parent: resolution.parent, base: resolution.base,
                          commits: resolution.commits, health: health, pullRequest: open ?? merged, mergedParent: mergedParent,
                          ahead: branch.ahead, behind: branch.behind, hasUpstream: branch.hasUpstreamRef,
                          isHEAD: branch.isHEAD && worktree == nil, worktreePath: worktree?.path, depth: depth)
    }

    /// `/tmp/x` and git's `/private/tmp/x` are the same worktree.
    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// The shared leading words of the branch names (`douwe/companion-18-…` → "companion"), else the root's name.
    static func stackName(_ names: [String]) -> String {
        guard let first = names.first else { return "" }
        let tokenized = names.map(words)
        var common = tokenized[0]
        for tokens in tokenized.dropFirst() {
            common = Array(zip(common, tokens).prefix { $0 == $1 }.map(\.0))
        }
        let endsAtFolder = common.last == "/"
        while let last = common.last, isSeparator(last) { common.removeLast() }
        let name = common.split(separator: "/").last.map { $0.joined() } ?? ""
        let rootName = first.split(separator: "/").last.map(String.init) ?? first
        // An owner folder alone (`douwe/`) or a bare number isn't a name.
        guard !endsAtFolder, !name.isEmpty, !name.allSatisfy({ $0.isNumber || isSeparator(String($0)) }) else { return rootName }
        return name
    }

    /// `douwe/companion-18` → ["douwe", "/", "companion", "-", "18"].
    private static func words(_ name: String) -> [String] {
        var tokens: [String] = []
        var word = ""
        for character in name {
            if isSeparator(String(character)) {
                if !word.isEmpty { tokens.append(word); word = "" }
                tokens.append(String(character))
            } else {
                word.append(character)
            }
        }
        if !word.isEmpty { tokens.append(word) }
        return tokens
    }

    private static func isSeparator(_ token: String) -> Bool { ["/", "-", "_", "."].contains(token) }
}

extension BranchInfo {
    nonisolated var hasUpstreamRef: Bool { !(upstream ?? "").isEmpty }
}
