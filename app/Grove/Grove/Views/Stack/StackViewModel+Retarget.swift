// Views/Stack/StackViewModel+Retarget.swift
// Grove
//
// A parent's pull request merged: move its children onto trunk, push them, point their PRs at trunk, drop the parent.

import Foundation

/// Children waiting on one merged parent.
struct MergedParent: Identifiable, Hashable {
    var id: String { branch }
    let branch: String
    let pullRequest: BranchPullRequest?
    let children: [StackLayer]
}

extension StackViewModel {

    func mergedParents(_ stack: BranchStack) -> [MergedParent] {
        let waiting = stack.layers.filter { $0.health.contains(.parentMerged) }
        let grouped = Dictionary(grouping: waiting) { $0.mergedParent?.headBranch ?? $0.parent ?? "" }
        return grouped.keys.sorted().map { branch in
            MergedParent(branch: branch, pullRequest: grouped[branch]?.first?.mergedParent, children: grouped[branch] ?? [])
        }
    }

    /// Rebases the children onto trunk (dropping the parent's commits, which trunk has in squashed form),
    /// pushes the ones already on the remote, and retargets their pull requests.
    func retarget(_ merged: MergedParent) async {
        guard let stack else { return }
        let trunk = stack.trunk
        await restack(stack, mode: .retarget(merged: merged.branch), title: "Retargeting onto \(trunk)")
        guard errorMessage == nil, await repository.pendingRestack() == nil, let fresh = self.stack ?? refs.stack(containing: stack.id)
        else { return }
        let moved = Set(merged.children.map(\.branch))
        let published = (refs.stack(containing: merged.children.first?.branch ?? "") ?? fresh).layers
            .filter { moved.contains($0.branch) && $0.hasUpstream && !$0.health.isDisjoint(with: [.unpushed, .diverged]) }
        if !published.isEmpty { await pushLayers(published, title: "Pushing retargeted branches") }
        guard errorMessage == nil else { return }
        await run("Retargeting pull requests") {
            for child in merged.children {
                guard let pr = child.pullRequest, !pr.isMerged, pr.baseBranch != trunk else { continue }
                try await self.repository.updatePullRequestBase(number: pr.number, base: trunk)
            }
        }
        await refs.refreshPullRequestsNow()
        if errorMessage == nil, refs.localBranches.contains(where: { $0.name == merged.branch }) {
            retargetedParent = merged.branch
        }
    }

    /// The merged branch still exists locally after a retarget; offered for deletion.
    func deleteMergedParent() async {
        guard let branch = retargetedParent else { return }
        retargetedParent = nil
        await run("Deleting \(branch)") {
            if self.refs.headBranch?.name == branch, let trunk = self.stack?.trunk {
                try await self.repository.checkout(branch: trunk)
            }
            try await self.repository.deleteBranch(name: branch, force: true)
        }
    }

    func keepMergedParent() { retargetedParent = nil }
}
