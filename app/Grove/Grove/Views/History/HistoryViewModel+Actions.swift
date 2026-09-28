// Views/History/HistoryViewModel+Actions.swift
// Grove

import Foundation

/// Something the user asked to do from the History tab that needs a sheet first.
enum HistoryAction: Identifiable {
    case createBranch(CommitInfo)
    case createTag(CommitInfo)
    case revert(CommitInfo)
    case reset(CommitInfo)
    case reword(CommitInfo)
    case squash(CommitInfo)
    case squashCommits([CommitInfo])
    case drop(CommitInfo)
    case fileHistory(String)
    case compare(BranchInfo)

    var id: String {
        switch self {
        case .createBranch(let c): "branch-\(c.id)"
        case .createTag(let c): "tag-\(c.id)"
        case .revert(let c): "revert-\(c.id)"
        case .reset(let c): "reset-\(c.id)"
        case .reword(let c): "reword-\(c.id)"
        case .squash(let c): "squash-\(c.id)"
        case .squashCommits(let commits): "squash-" + commits.map(\.id).joined(separator: "-")
        case .drop(let c): "drop-\(c.id)"
        case .fileHistory(let path): "file-\(path)"
        case .compare(let branch): "compare-\(branch.id)"
        }
    }
}

extension HistoryViewModel {

    func request(_ action: HistoryAction) {
        errorMessage = nil
        setPendingAction(action)
    }

    func dismissAction() {
        setPendingAction(nil)
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Mutations

    func cherryPick(_ commit: CommitInfo) async {
        await perform { try await $0.cherryPick(commit: commit.id) }
    }

    func revert(_ commit: CommitInfo) async {
        await perform { try await $0.revert(commit: commit.id) }
    }

    func reset(to commit: CommitInfo, mode: ResetMode) async {
        await perform { try await $0.resetToCommit(commit.id, mode: mode) }
    }

    /// Called by the create branch/tag sheets after they wrote the ref themselves.
    func refCreated() async {
        dismissAction()
        await repositoryChanged()
    }

    func perform(_ operation: (any GitRepositoryProtocol) async throws -> Void) async {
        setPerforming(true)
        defer { setPerforming(false) }
        do {
            try await operation(repository)
            dismissAction()
        } catch {
            errorMessage = error.localizedDescription
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
