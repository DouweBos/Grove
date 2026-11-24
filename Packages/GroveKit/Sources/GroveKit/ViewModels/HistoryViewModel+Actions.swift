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

    /// Every listed commit, as ⌘A selects them.
    public func selectAll() {
        var next = selection
        next.selectAll(in: filteredCommits.map(\.id))
        applySelection(next)
    }

    /// The File History of `path`, wired to this list's hooks.
    public func fileHistory(path: String) -> FileHistoryViewModel {
        let history = FileHistoryViewModel(repository: repository, filePath: path)
        history.onRepositoryChanged = onRepositoryChanged
        history.onAction = onAction
        // Without an app that opens blame, File History offers none.
        if onOpenBlame != nil {
            history.onOpenBlame = { [weak self] file, revision in
                // Blame replaces History, whose sheet would come back on returning to it.
                self?.dismissAction()
                await self?.onOpenBlame?(file, revision)
            }
        }
        return history
    }

    public func dismissError() {
        if let errorMessage { dismissedError = errorMessage }
        errorMessage = nil
    }

    // MARK: - Mutations

    public func cherryPick(_ commit: CommitInfo) async {
        await perform(.cherryPick, .cherryPick(commit.id))
    }

    public func revert(_ commit: CommitInfo) async {
        await perform(.revert, .revert(commit.id))
    }

    /// Detaches HEAD at the commit, e.g. a force-pushed remote tip to look at before resetting a branch to it.
    public func checkout(_ commit: CommitInfo) async {
        await perform(.checkout, .checkout(commit.id))
    }

    /// Reset moves HEAD's branch, so it's offered only where the list shows that branch.
    public var canReset: Bool { filterBranch == nil || filterBranch == headBranchName }

    public func reset(to commit: CommitInfo, mode: ResetMode) async {
        await perform(.reset, .reset(to: commit.id, mode: mode))
    }

    /// Called by the create branch/tag sheets after they wrote the ref themselves.
    public func refCreated() async {
        dismissAction()
        await repositoryChanged()
    }

    func perform(_ action: GroveKitAction, _ command: GitCommand, before: (() async -> Void)? = nil,
                 after: (() async -> Void)? = nil) async {
        setPerforming(true)
        defer { setPerforming(false) }
        await before?()
        do {
            try await commands.perform(command)
            await after?()
            dismissAction()
            onAction?(action, true)
        } catch {
            errorMessage = error.localizedDescription
            onAction?(action, false)
        }
        await repositoryChanged()
        // A conflict stops the operation; Changes is where it's resolved and continued.
        if repository.repositoryState != .normal {
            dismissAction()
            onRebaseStopped?()
        }
    }

    private func repositoryChanged() async {
        if let onRepositoryChanged {
            await onRepositoryChanged()
        } else {
            await reload()
        }
    }
}
