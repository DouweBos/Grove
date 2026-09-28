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

    /// History rewrites run an interactive rebase from the commit to HEAD, so they
    /// only make sense for non-merge commits on the checked-out branch.
    func canRewrite(_ commit: CommitInfo) -> Bool {
        filterBranch == nil && !commit.isMerge
    }

    func canSquashWithParent(_ commit: CommitInfo) -> Bool {
        guard canRewrite(commit), let parentID = commit.parentIDs.first,
              let parent = self.commit(withID: parentID) else { return false }
        return !parent.isMerge
    }

    /// Message proposed when squashing: the parent's message followed by this commit's.
    func squashMessage(for commit: CommitInfo) -> String {
        let parent = commit.parentIDs.first.flatMap { self.commit(withID: $0) }
        return [parent?.message, commit.message].compactMap { $0 }.joined(separator: "\n\n")
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

    func reword(_ commit: CommitInfo, message: String) async {
        await performRewrite("Reword \(commit.shortSHA)") { try await $0.rewordCommit(commit.id, newMessage: message) }
    }

    func squashWithParent(_ commit: CommitInfo, message: String) async {
        guard let parent = commit.parentIDs.first else { return }
        await performRewrite("Squash \(commit.shortSHA)") { try await $0.squashCommits([parent, commit.id], message: message) }
    }

    func drop(_ commit: CommitInfo) async {
        await performRewrite("Delete \(commit.shortSHA)") { try await $0.dropCommit(commit.id) }
    }

    /// Undo resets --hard to the old HEAD, so it's only recorded when that can't lose uncommitted work.
    private func performRewrite(_ description: String,
                                _ operation: @escaping (any GitRepositoryProtocol) async throws -> Void) async {
        let repo = repository
        let oldHead = try? await repo.commitDetail("HEAD").id
        let wasClean = (try? await GitUndoManager.isWorkingTreeClean(repo)) ?? false
        await perform { repo in
            try await operation(repo)
            guard wasClean, let oldHead, let newHead = try? await repo.commitDetail("HEAD").id else { return }
            self.undoManager?.record(GitUndoManager.rewriteAction(
                description: description, oldHead: oldHead, newHead: newHead, repository: repo))
        }
    }

    /// Called by the create branch/tag sheets after they wrote the ref themselves.
    func refCreated() async {
        dismissAction()
        await repositoryChanged()
    }

    private func perform(_ operation: (any GitRepositoryProtocol) async throws -> Void) async {
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
