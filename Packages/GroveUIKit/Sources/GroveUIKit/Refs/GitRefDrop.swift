// Refs/GitRefDrop.swift
// GroveUIKit
//
// Dragging refs onto each other: every drop asks for confirmation in a sheet, then runs through the commands.

#if os(macOS)
import GroveKit
import SwiftUI

/// What a drop in the sidebar will do once confirmed.
public enum GitRefDrop: Identifiable, Equatable {
    /// Merge `source` into `target`, checking `target` out first when it isn't.
    case merge(source: String, target: String)
    /// Rebase `target` onto `onto`, checking `target` out first when it isn't.
    case rebase(target: String, onto: String)
    /// Bring `remoteBranch` (e.g. `origin/main`) into local `target`.
    case pull(remoteBranch: String, target: String)
    /// Push local `branch` to `remote`.
    case push(branch: String, remote: String)
    /// One the app runs itself.
    case custom(GitRefCustomDrop)

    public var id: String {
        switch self {
        case .merge(let source, let target): "merge-\(source)-\(target)"
        case .rebase(let target, let onto): "rebase-\(target)-\(onto)"
        case .pull(let remoteBranch, let target): "pull-\(remoteBranch)-\(target)"
        case .push(let branch, let remote): "push-\(branch)-\(remote)"
        case .custom(let drop): "custom-\(drop.id)"
        }
    }
}

/// A drop the app runs its own way, confirmed in the kit's sheet.
public struct GitRefCustomDrop: Identifiable, Equatable {
    public let id: String
    public var title: String
    public var message: String
    public var symbol: String
    public var primaryTitle: String
    /// The sheet's rows, e.g. `("Move", "feature/a")`.
    public var fields: [(label: String, value: String)]
    /// Throws to keep the sheet open with the error.
    public var run: () async throws -> Void

    public init(id: String, title: String, message: String, symbol: String, primaryTitle: String,
                fields: [(label: String, value: String)], run: @escaping () async throws -> Void) {
        self.id = id
        self.title = title
        self.message = message
        self.symbol = symbol
        self.primaryTitle = primaryTitle
        self.fields = fields
        self.run = run
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

extension GitRefsModel {

    /// A dragged ref dropped on local branch `target`: another local branch merges (Option rebases), a remote branch pulls.
    public func handleDrop(_ payload: String, onBranch target: BranchInfo, option: Bool,
                           host: GitRefsHost = GitRefsHost()) -> Bool {
        guard payload != target.name else { return false }
        if let custom = host.drop?(payload, target, option) {
            requestDrop(.custom(custom))
            return true
        }
        let features = actions.commands.features
        let isHEAD = target.name == headName
        if refs.localBranches.contains(where: { $0.name == payload }) {
            let feature: GitFeature = option ? .rebase : .merge
            guard features.contains(feature), isHEAD || features.contains(.checkout) else { return false }
            requestDrop(option ? .rebase(target: target.name, onto: payload) : .merge(source: payload, target: target.name))
            return true
        }
        if refs.remoteBranches.contains(where: { $0.name == payload }) {
            guard isHEAD || features.contains(.editBranches) else { return false }
            requestDrop(.pull(remoteBranch: payload, target: target.name))
            return true
        }
        return false
    }

    /// A local branch dropped on a remote pushes it there.
    public func handleDrop(_ payload: String, onRemote remote: RemoteInfo) -> Bool {
        guard actions.commands.features.contains(.push), refs.localBranches.contains(where: { $0.name == payload }) else {
            return false
        }
        requestDrop(.push(branch: payload, remote: remote.name))
        return true
    }

    public func requestDrop(_ action: GitRefDrop) {
        dropError = nil
        pendingDrop = action
    }

    public func cancelDrop() {
        pendingDrop = nil
        dropError = nil
    }

    /// Runs the confirmed drop. Failures stay in the sheet; the repository refreshes either way,
    /// since a conflicted merge or rebase still changed it.
    public func confirmDrop(pullStrategy: PullStrategy = .merge, remoteBranchName: String? = nil,
                            setUpstream: Bool = false) async {
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
        await actions.didChangeRepository()
    }

    private func perform(_ action: GitRefDrop, pullStrategy: PullStrategy, remoteBranchName: String?,
                         setUpstream: Bool) async throws {
        let commands = actions.commands
        switch action {
        case .merge(let source, let target):
            try await checkOutIfNeeded(target)
            try await commands.perform(.merge(source, squash: false))
        case .rebase(let target, let onto):
            try await checkOutIfNeeded(target)
            try await commands.perform(.rebase(onto: onto))
        case .pull(let remoteBranch, let target):
            guard let remote = refs.remoteBranches.first(where: { $0.name == remoteBranch }),
                  let remoteName = remote.remoteName else { return }
            let branch = RefActionsViewModel.shortName(of: remote)
            if target == headName {
                try await commands.perform(.pull(remote: remoteName, branch: branch, strategy: pullStrategy, options: PullOptions()))
            } else {
                try await commands.perform(.fastForward(branch: target, remote: remoteName, remoteBranch: branch))
            }
        case .push(let branch, let remote):
            let name = remoteBranchName?.trimmingCharacters(in: .whitespaces) ?? ""
            try await commands.perform(.pushBranch(branch, remote: remote, as: name.isEmpty ? branch : name,
                                                   forceWithLease: false, setUpstream: setUpstream, options: PushOptions()))
        case .custom(let drop):
            try await drop.run()
        }
    }

    private func checkOutIfNeeded(_ branch: String) async throws {
        guard branch != headName else { return }
        let previous = headName
        try await actions.commands.perform(.checkout(branch))
        if let previous {
            actions.undoManager?.record(GitUndoManager.checkoutAction(targetBranch: branch, previousBranch: previous,
                                                                      repository: actions.repository, commands: actions.commands))
        }
    }
}
#endif
