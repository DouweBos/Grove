// ViewModels/HistoryViewModel+Rewrite.swift
// GroveKit

import Foundation

/// History rewrites: reword, squash, drop, all run as a scripted interactive rebase.
extension HistoryViewModel {

    /// History rewrites run an interactive rebase from the commit to HEAD, so they
    /// only make sense for non-merge commits on the checked-out branch, not ones only its upstream has.
    func canRewrite(_ commit: CommitInfo) -> Bool {
        filterBranch == nil && !commit.isMerge && firstParentLine(reaching: [commit.id]).contains(commit.id)
    }

    func canSquashWithParent(_ commit: CommitInfo) -> Bool {
        guard canRewrite(commit), let parentID = commit.parentIDs.first,
              let parent = self.commit(withID: parentID) else { return false }
        return !parent.isMerge
    }

    /// Squashing a selection needs an unbroken run of non-merge commits on HEAD's first-parent line.
    func canSquash(_ commits: [CommitInfo]) -> Bool {
        guard filterBranch == nil, commits.count >= 2, !commits.contains(where: \.isMerge) else { return false }
        let line = firstParentLine(reaching: Set(commits.map(\.id)))
        guard let start = line.firstIndex(where: { id in commits.contains { $0.id == id } }),
              start + commits.count <= line.count else { return false }
        return Set(line[start..<start + commits.count]) == Set(commits.map(\.id))
    }

    /// Loaded commits from HEAD along first parents, stopping once every `targets` SHA is passed.
    func firstParentLine(reaching targets: Set<String> = []) -> [String] {
        let byID = Dictionary(commits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var line: [String] = []
        var remaining = targets
        var next = headSHA
        while let id = next, let commit = byID[id] {
            line.append(id)
            remaining.remove(id)
            if !targets.isEmpty, remaining.isEmpty { break }
            next = commit.parentIDs.first
        }
        return line
    }

    /// Message proposed when squashing: the parent's message followed by this commit's.
    func squashMessage(for commit: CommitInfo) -> String {
        let parent = commit.parentIDs.first.flatMap { self.commit(withID: $0) }
        return [parent?.message, commit.message].compactMap { $0 }.joined(separator: "\n\n")
    }

    /// Every message, oldest first, the order git itself proposes.
    func squashMessage(for commits: [CommitInfo]) -> String {
        commits.reversed().map(\.message).joined(separator: "\n\n")
    }

    /// Commits the upstream already has; rewriting them means force-pushing over shared history.
    func pushedCommits(in commits: [CommitInfo]) -> [CommitInfo] {
        guard upstreamName != nil else { return [] }
        return commits.filter { !outgoingSHAs.contains($0.id) && !incomingSHAs.contains($0.id) }
    }

    /// Warns before rewriting `commits` when some are already pushed.
    func pushedWarning(for commits: [CommitInfo]) -> String? {
        let pushed = pushedCommits(in: commits).count
        guard pushed > 0 else { return nil }
        return "\(pushed) of these commit\(pushed == 1 ? " is" : "s are") already on \(upstreamName ?? "the upstream"); "
            + "pushing afterwards needs a force push."
    }

    /// How many commits a rewrite starting at `oldest` replaces: it and everything above it on HEAD's line.
    func rewrittenCount(from oldest: CommitInfo) -> Int {
        let line = firstParentLine(reaching: [oldest.id])
        return (line.firstIndex(of: oldest.id) ?? 0) + 1
    }

    /// Commits an interactive rebase onto `base` replays: those above it on HEAD's line, newest first.
    /// Nil when `base` isn't on that line or a merge sits above it, which a linear plan would flatten.
    func rebaseCandidates(onto base: CommitInfo) -> [CommitInfo]? {
        guard filterBranch == nil else { return nil }
        let line = firstParentLine(reaching: [base.id])
        guard let index = line.firstIndex(of: base.id), index > 0 else { return nil }
        let above = line[..<index].compactMap { commit(withID: $0) }
        return above.contains(where: \.isMerge) ? nil : above
    }

    func canRebaseInteractively(onto base: CommitInfo) -> Bool {
        rebaseCandidates(onto: base) != nil
    }

    // MARK: - Mutations

    /// `plan` is oldest first. A conflict leaves the rebase stopped and hands over to the Changes banner.
    func rebaseInteractively(onto base: CommitInfo, plan: [RebaseStep]) async {
        if let problem = RebasePlan.problem(with: plan) { return errorMessage = problem }
        await performRewrite("Interactive Rebase") { try await $0.rebaseInteractive(onto: base.id, steps: plan) }
        guard repository.repositoryState != .normal else { return }
        dismissAction()
        onRebaseStopped?()
    }

    func reword(_ commit: CommitInfo, message: String) async {
        await performRewrite("Reword \(commit.shortSHA)") { try await $0.rewordCommit(commit.id, newMessage: message) }
    }

    func squashWithParent(_ commit: CommitInfo, message: String) async {
        guard let parent = commit.parentIDs.first else { return }
        await performRewrite("Squash \(commit.shortSHA)") { try await $0.squashCommits([parent, commit.id], message: message) }
    }

    /// `commits` as listed, newest first; git squashes them oldest first.
    func squash(_ commits: [CommitInfo], message: String) async {
        let oldestFirst = commits.reversed().map(\.id)
        await performRewrite("Squash \(commits.count) Commits") { try await $0.squashCommits(oldestFirst, message: message) }
    }

    func drop(_ commit: CommitInfo) async {
        await performRewrite("Delete \(commit.shortSHA)") { try await $0.dropCommit(commit.id) }
    }

    /// Undo resets --hard to the old HEAD, so it's only recorded when that can't lose uncommitted work.
    func performRewrite(_ description: String,
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
}
