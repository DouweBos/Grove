// Views/Sidebar/SidebarViewModel+Drops.swift
// Grove
//
// Dragging refs onto each other in the sidebar: every drop asks for confirmation in a sheet before git runs.

import Foundation

/// What a drop in the sidebar will do once confirmed.
enum SidebarDropAction: Identifiable, Equatable {
    /// Merge `source` into `target`, checking `target` out first when it isn't.
    case merge(source: String, target: String)
    /// Rebase `target` onto `onto`, checking `target` out first when it isn't.
    case rebase(target: String, onto: String)
    /// Bring `remoteBranch` (e.g. `origin/main`) into local `target`.
    case pull(remoteBranch: String, target: String)
    /// Push local `branch` to `remote`.
    case push(branch: String, remote: String)

    var id: String {
        switch self {
        case .merge(let source, let target): "merge-\(source)-\(target)"
        case .rebase(let target, let onto): "rebase-\(target)-\(onto)"
        case .pull(let remoteBranch, let target): "pull-\(remoteBranch)-\(target)"
        case .push(let branch, let remote): "push-\(branch)-\(remote)"
        }
    }
}

extension SidebarViewModel {

    /// A dragged ref dropped on local branch `target`: another local branch merges (Option rebases), a remote branch pulls.
    func handleDrop(_ payload: String, onBranch target: BranchInfo, option: Bool) -> Bool {
        guard payload != target.name else { return false }
        if localBranches.contains(where: { $0.name == payload }) {
            requestDrop(option ? .rebase(target: target.name, onto: payload) : .merge(source: payload, target: target.name))
            return true
        }
        if remoteBranches.contains(where: { $0.name == payload }) {
            requestDrop(.pull(remoteBranch: payload, target: target.name))
            return true
        }
        return false
    }

    /// A local branch dropped on a remote pushes it there.
    func handleDrop(_ payload: String, onRemote remote: RemoteInfo) -> Bool {
        guard localBranches.contains(where: { $0.name == payload }) else { return false }
        requestDrop(.push(branch: payload, remote: remote.name))
        return true
    }

    func requestDrop(_ action: SidebarDropAction) {
        dropError = nil
        pendingDrop = action
    }

    func cancelDrop() {
        pendingDrop = nil
        dropError = nil
    }

    var headName: String? { localBranches.first(where: \.isHEAD)?.name }

    /// Runs the confirmed drop. Failures stay in the sheet; the repository refreshes either way,
    /// since a conflicted merge or rebase still changed it.
    func confirmDrop(pullStrategy: PullStrategy = .merge, remoteBranchName: String? = nil, setUpstream: Bool = false) async {
        guard let action = pendingDrop else { return }
        isRunningDrop = true
        dropError = nil
        defer { isRunningDrop = false }
        do {
            try await perform(action, pullStrategy: pullStrategy, remoteBranchName: remoteBranchName, setUpstream: setUpstream)
            pendingDrop = nil
        } catch {
            dropError = error.localizedDescription
        }
        await didChangeRepository()
    }

    private func perform(_ action: SidebarDropAction, pullStrategy: PullStrategy, remoteBranchName: String?,
                         setUpstream: Bool) async throws {
        switch action {
        case .merge(let source, let target):
            try await checkOutIfNeeded(target)
            try await repository.merge(branch: source)
        case .rebase(let target, let onto):
            try await checkOutIfNeeded(target)
            try await repository.rebase(onto: onto)
        case .pull(let remoteBranch, let target):
            guard let remote = remoteBranches.first(where: { $0.name == remoteBranch }), let remoteName = remote.remoteName else { return }
            let branch = Self.shortName(of: remote)
            if target == headName {
                try await repository.pull(remote: remoteName, branch: branch, strategy: pullStrategy, options: PullOptions(), progress: nil)
            } else {
                try await repository.fastForward(branch: target, fromRemote: remoteName, branch: branch)
            }
        case .push(let branch, let remote):
            let name = remoteBranchName?.trimmingCharacters(in: .whitespaces)
            try await repository.push(branch: branch, to: remote, as: name?.isEmpty == false ? name! : branch, setUpstream: setUpstream)
        }
    }

    private func checkOutIfNeeded(_ branch: String) async throws {
        guard branch != headName else { return }
        let previous = headName
        try await repository.checkout(branch: branch)
        if let previous {
            undoManager?.record(GitUndoManager.checkoutAction(targetBranch: branch, previousBranch: previous, repository: repository))
        }
    }
}
