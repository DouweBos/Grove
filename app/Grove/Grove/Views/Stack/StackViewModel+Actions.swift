// Views/Stack/StackViewModel+Actions.swift
// Grove
//
// Layer actions in the Stack tab: push, check out, pull requests, move onto another branch, fold into the parent.

import Foundation

extension StackViewModel {

    /// Layers with commits their remote branch lacks, or none at all.
    func changedLayers(_ stack: BranchStack) -> [StackLayer] {
        stack.layers.filter { !$0.health.isDisjoint(with: [.unpushed, .diverged]) }
    }

    /// Force-with-lease on every changed layer at once, so a push that loses a race changes nothing.
    func pushStack() async {
        guard let stack else { return }
        await pushLayers(changedLayers(stack), title: "Pushing \(stack.name)")
    }

    func push(_ layer: StackLayer) async {
        await pushLayers([layer], title: "Pushing \(layer.branch)")
    }

    func pushLayers(_ layers: [StackLayer], title: String) async {
        guard !layers.isEmpty, let remote = StackReader.primaryRemote(refs.remotes) else {
            errorMessage = refs.remotes.isEmpty ? "Add a remote to push to." : nil
            return
        }
        let pushes = layers.map { layer -> StackPush in
            let branch = refs.localBranches.first { $0.name == layer.branch }
            let upstream = branch?.upstreamShortName.flatMap { $0.hasPrefix(remote + "/") ? String($0.dropFirst(remote.count + 1)) : nil }
            let remoteName = upstream ?? layer.branch
            let expected = refs.remoteBranches.first { $0.name == "\(remote)/\(remoteName)" }?.targetSHA
            return StackPush(branch: layer.branch, remoteBranch: remoteName, expectedSHA: expected)
        }
        await run(title) { try await self.repository.pushStack(pushes, to: remote) }
    }

    func checkOut(_ layer: StackLayer) async {
        await run("Checking out \(layer.branch)") { try await self.repository.checkout(branch: layer.branch) }
    }

    func createPullRequest(for layer: StackLayer) {
        onCreatePullRequest?(layer.branch)
    }

    /// Other branches `layer` could be moved onto: trunk and every branch outside its own subtree.
    func moveTargets(for layer: StackLayer) -> [String] {
        let subtree = Set(stack?.subtree(from: layer.branch).map(\.branch) ?? [])
        return refs.localBranches.map(\.name).filter { !subtree.contains($0) && $0 != layer.parent }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func move(_ layer: StackLayer, onto target: String) async {
        guard let stack else { return }
        await restack(stack, mode: .move(layer.branch, onto: target), title: "Moving \(layer.branch) onto \(target)")
    }

    /// Only a layer sitting right on its parent can fold: the parent fast-forwards over it, then the branch goes.
    func canFold(_ layer: StackLayer) -> Bool {
        guard let parent = layer.parent, stack?.layer(parent) != nil else { return false }
        return !layer.health.contains(.needsRestack) && layer.worktreePath == nil
    }

    func fold(_ layer: StackLayer) async {
        guard canFold(layer), let parent = layer.parent, let parentLayer = stack?.layer(parent) else { return }
        await run("Folding \(layer.branch) into \(parent)") {
            try await self.repository.fastForward(branch: parent, to: layer.tipSHA, worktreePath: parentLayer.worktreePath)
            if layer.isHEAD { try await self.repository.checkout(branch: parent) }
            try await self.repository.deleteBranch(name: layer.branch, force: true)
        }
    }

    func run(_ title: String, _ work: @escaping () async throws -> Void) async {
        activity = title
        defer { activity = nil }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
        await onRepositoryChanged?()
    }
}
