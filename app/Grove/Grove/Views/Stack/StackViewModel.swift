// Views/Stack/StackViewModel.swift
// Grove
//
// The Stack tab: which stack is shown, and each layer's diff stats and commits, read on demand.

import Foundation
import Observation

@MainActor
@Observable
final class StackViewModel {

    let refs: RepositoryRefs
    let repository: any GitRepositoryProtocol
    var onRepositoryChanged: (() async -> Void)?

    /// The branch last picked in the sidebar or the tab's menu; HEAD's stack when nil or no longer stacked.
    private(set) var focusedBranch: String?
    private(set) var expandedLayers: Set<String> = []
    /// Keyed by `base..tip`, so a layer that didn't move keeps its numbers.
    private(set) var stats: [String: DiffStats] = [:]
    private(set) var layerCommits: [String: [CommitInfo]] = [:]
    var errorMessage: String?

    init(repository: any GitRepositoryProtocol, refs: RepositoryRefs) {
        self.repository = repository
        self.refs = refs
    }

    var stacks: [BranchStack] { refs.stacks }

    var stack: BranchStack? {
        if let focusedBranch, let stack = refs.stack(containing: focusedBranch) { return stack }
        if let head = refs.headBranch, let stack = refs.stack(containing: head.name) { return stack }
        return refs.stacks.first
    }

    func focus(branch: String) {
        guard refs.stack(containing: branch) != nil else { return }
        focusedBranch = branch
    }

    func show(_ stack: BranchStack) {
        focusedBranch = stack.layers.first?.branch
    }

    func toggleExpanded(_ layer: StackLayer) {
        if expandedLayers.contains(layer.branch) {
            expandedLayers.remove(layer.branch)
        } else {
            expandedLayers.insert(layer.branch)
            Task { await loadCommits(layer) }
        }
    }

    func stats(for layer: StackLayer) -> DiffStats? { stats[Self.key(layer)] }

    func commits(for layer: StackLayer) -> [CommitInfo]? { layerCommits[Self.key(layer)] }

    /// Reads diff stats for the shown stack's layers that moved since the last read.
    func refresh() async {
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

    func dismissError() { errorMessage = nil }

    private static func key(_ layer: StackLayer) -> String { "\(layer.base)..\(layer.tipSHA)" }
}
