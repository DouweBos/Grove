// ViewModels/StackViewModel.swift
// GroveKit
//
// The Stack tab: which stack is shown, and each layer's diff stats and commits, read on demand.

import Foundation
import Observation

@MainActor
@Observable
public final class StackViewModel {

    public let refs: RepositoryRefs
    public let repository: any GitRepositoryProtocol
    public var onRepositoryChanged: (() async -> Void)?
    /// Reports each action this view model runs, e.g. to the app's telemetry.
    @ObservationIgnored public var onAction: GroveKitActionHandler?
    /// A layer conflicted mid-cascade; the session switches to Changes, where the banner continues it.
    public var onRestackStopped: (() -> Void)?
    public var onCreatePullRequest: ((String) -> Void)?
    /// Selects a stack by id in the sidebar, which in turn focuses it here.
    public var onShowStack: ((String) -> Void)?
    public var activity: String?
    /// A merged parent whose children were just retargeted, offered for deletion.
    public var retargetedParent: String?

    /// The branch last picked in the sidebar or the tab's menu; HEAD's stack when nil or no longer stacked.
    private(set) var focusedBranch: String?
    public private(set) var expandedLayers: Set<String> = []
    /// Keyed by `base..tip`, so a layer that didn't move keeps its numbers.
    public private(set) var stats: [String: DiffStats] = [:]
    private(set) var layerCommits: [String: [CommitInfo]] = [:]
    public var errorMessage: String?

    public init(repository: any GitRepositoryProtocol, refs: RepositoryRefs) {
        self.repository = repository
        self.refs = refs
    }

    public var stacks: [BranchStack] { refs.stacks }

    public var stack: BranchStack? {
        if let focusedBranch, let stack = refs.stack(containing: focusedBranch) { return stack }
        if let head = refs.headBranch, let stack = refs.stack(containing: head.name) { return stack }
        return refs.stacks.first
    }

    public func focus(branch: String) {
        guard refs.stack(containing: branch) != nil else { return }
        focusedBranch = branch
    }

    /// Stacks whose name or a layer's branch contains the query.
    public func stacks(matching query: String) -> [BranchStack] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return stacks }
        return stacks.filter { stack in
            stack.name.localizedCaseInsensitiveContains(query)
                || stack.layers.contains { $0.branch.localizedCaseInsensitiveContains(query) }
        }
    }

    public func show(_ stack: BranchStack) {
        focus(branch: stack.id)
        onShowStack?(stack.id)
    }

    public func toggleExpanded(_ layer: StackLayer) {
        if expandedLayers.contains(layer.branch) {
            expandedLayers.remove(layer.branch)
        } else {
            expandedLayers.insert(layer.branch)
            Task { await loadCommits(layer) }
        }
    }

    public func stats(for layer: StackLayer) -> DiffStats? { stats[Self.key(layer)] }

    public func commits(for layer: StackLayer) -> [CommitInfo]? { layerCommits[Self.key(layer)] }

    /// Reads diff stats for the shown stack's layers that moved since the last read.
    public func refresh() async {
        guard let stack else { return }
        for layer in stack.layers where stats[Self.key(layer)] == nil && !layer.base.isEmpty {
            if let read = try? await repository.diffStats(from: layer.base, to: layer.tipSHA) {
                stats[Self.key(layer)] = read
            }
        }
        for layer in stack.layers where expandedLayers.contains(layer.branch) { await loadCommits(layer) }
    }

    private func loadCommits(_ layer: StackLayer) async {
        let key = Self.key(layer)
        guard layerCommits[key] == nil else { return }
        let range = layer.base.isEmpty ? [layer.tipSHA] : [layer.tipSHA, "^\(layer.base)"]
        do {
            layerCommits[key] = try await repository.log(maxCount: 200, skip: 0, revisions: range)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func dismissError() { errorMessage = nil }

    // MARK: - Restack

    public var isBusy: Bool { activity != nil }

    public func canRestack(_ stack: BranchStack) -> Bool {
        stack.layers.contains { $0.health.contains(.needsRestack) }
    }

    /// Fixes only the layers that drifted from their parent, and whatever sits on them.
    public func restackDrifted() async {
        guard let stack else { return }
        await restack(stack, mode: .drifted, title: "Restacking \(stack.name)")
    }

    public func restack(from layer: StackLayer) async {
        guard let stack else { return }
        await restack(stack, mode: .from(layer.branch), title: "Restacking \(layer.branch)")
    }

    /// Fetches, then moves the whole stack onto trunk's new tip.
    public func sync() async {
        guard let stack else { return }
        activity = "Fetching"
        do {
            try await repository.fetch(remote: nil, progress: nil)
        } catch {
            activity = nil
            errorMessage = error.localizedDescription
            return
        }
        await onRepositoryChanged?()
        guard let fresh = self.stack ?? refs.stack(containing: stack.id) else { activity = nil; return }
        await restack(fresh, mode: .ontoTrunk, title: "Syncing \(fresh.name)")
    }

    public func restack(_ stack: BranchStack, mode: RestackMode, title: String) async {
        activity = title
        defer { activity = nil }
        let plan = RestackPlan.make(stack, mode: mode, trunkRef: await trunkRef(stack.trunk), headBranch: refs.headBranch?.name)
        do {
            try await repository.restack(plan)
            onAction?(.restack, true)
        } catch RestackError.stopped {
            onAction?(.restack, false)
            onRestackStopped?()
        } catch {
            errorMessage = error.localizedDescription
            onAction?(.restack, false)
        }
        await onRepositoryChanged?()
    }

    /// The remote's trunk once it has moved past the local one, which people rarely pull; else the local branch.
    func trunkRef(_ trunk: String) async -> String {
        let local = "refs/heads/\(trunk)"
        guard let remote = refs.remoteBranches.first(where: { $0.name == "\(StackReader.primaryRemote(refs.remotes) ?? "origin")/\(trunk)" })
        else { return local }
        let hasLocal = refs.localBranches.contains { $0.name == trunk }
        if hasLocal, await repository.isAncestor(remote.id, of: local) { return local }
        return remote.id
    }

    private static func key(_ layer: StackLayer) -> String { "\(layer.base)..\(layer.tipSHA)" }
}
