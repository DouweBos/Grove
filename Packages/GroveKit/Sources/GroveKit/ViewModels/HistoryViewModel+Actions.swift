// ViewModels/HistoryViewModel+Actions.swift
// GroveKit

import Foundation

/// Something the user asked to do from the History tab that needs a sheet first.
public enum HistoryAction: Identifiable {
    case createBranch(CommitInfo)
    case createTag(CommitInfo)
    case revert(CommitInfo)
    case reset(CommitInfo)
    case reword(CommitInfo)
    case squash(CommitInfo)
    case squashCommits([CommitInfo])
    case interactiveRebase(CommitInfo)
    case drop(CommitInfo)
    case fileHistory(String)
    case compare(BranchInfo)

    public var id: String {
        switch self {
        case .createBranch(let c): "branch-\(c.id)"
        case .createTag(let c): "tag-\(c.id)"
        case .revert(let c): "revert-\(c.id)"
        case .reset(let c): "reset-\(c.id)"
        case .reword(let c): "reword-\(c.id)"
        case .squash(let c): "squash-\(c.id)"
        case .interactiveRebase(let base): "rebase-\(base.id)"
        case .squashCommits(let commits): "squash-" + commits.map(\.id).joined(separator: "-")
        case .drop(let c): "drop-\(c.id)"
        case .fileHistory(let path): "file-\(path)"
        case .compare(let branch): "compare-\(branch.id)"
        }
    }
}

extension HistoryViewModel {

    public func request(_ action: HistoryAction) {
        errorMessage = nil
        setPendingAction(action)
    }

    public func dismissAction() {
        setPendingAction(nil)
    }

    public func dismissError() {
        errorMessage = nil
    }

    // MARK: - Mutations

    public func cherryPick(_ commit: CommitInfo) async {
        await perform(.cherryPick) { try await $0.cherryPick(commit: commit.id) }
    }

    public func revert(_ commit: CommitInfo) async {
        await perform(.revert) { try await $0.revert(commit: commit.id) }
    }

    public func reset(to commit: CommitInfo, mode: ResetMode) async {
        await perform(.reset) { try await $0.resetToCommit(commit.id, mode: mode) }
    }

    /// Called by the create branch/tag sheets after they wrote the ref themselves.
    public func refCreated() async {
        dismissAction()
        await repositoryChanged()
    }

    func perform(_ action: GroveKitAction, _ operation: (any GitRepositoryProtocol) async throws -> Void) async {
        setPerforming(true)
        defer { setPerforming(false) }
        do {
            try await operation(repository)
            dismissAction()
            onAction?(action, true)
        } catch {
            errorMessage = error.localizedDescription
            onAction?(action, false)
        }
        await repositoryChanged()
    }

    private func repositoryChanged() async {
        if let onRepositoryChanged {
            await onRepositoryChanged()
        } else {
            await reload()
        }
    }
}
