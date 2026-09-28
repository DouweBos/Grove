// Views/PullRequests/CreatePullRequestViewModel.swift
// Grove

import Foundation
import Observation

/// The "Create Pull Request" sheet: branches, a title and body prefilled from the head's commits, and submission.
@MainActor
@Observable
final class CreatePullRequestViewModel: Identifiable {

    let id = UUID()
    private(set) var head: String
    private(set) var base = ""
    private(set) var title = ""
    private(set) var body = ""
    private(set) var reviewersText = ""
    private(set) var isDraft = false
    /// Commits on the head that the base lacks, newest first.
    private(set) var commits: [CommitInfo] = []
    private(set) var isLoadingCommits = false
    private(set) var progressTitle: String?
    private(set) var errorMessage: String?
    private(set) var isConfirmingPush = false
    // Once edited, a field keeps what the user typed when the branches change.
    private var isTitleEdited = false
    private var isBodyEdited = false
    /// The head came from a branch the user picked, rather than the checked-out one.
    private let isHeadExplicit: Bool

    let repository: any GitRepositoryProtocol
    let refs: RepositoryRefs
    /// Called with the new pull request's URL once the host accepted it.
    var onCreated: ((String) async -> Void)?

    init(repository: any GitRepositoryProtocol, refs: RepositoryRefs, head: String?) {
        self.repository = repository
        self.refs = refs
        self.head = head ?? repository.currentBranch?.name ?? refs.localBranches.first?.name ?? ""
        isHeadExplicit = head != nil
    }

    // MARK: Derived

    var headBranch: BranchInfo? { refs.localBranches.first { $0.name == head } }

    /// The head's tracked remote, else origin, else the first remote.
    var remote: String {
        if let tracked = headBranch?.upstreamRemoteName { return tracked }
        return refs.remotes.first { $0.name == "origin" }?.name ?? refs.remotes.first?.name ?? "origin"
    }

    /// The head's name on the remote: its upstream's when it tracks one there.
    var remoteHead: String {
        if let upstream = headBranch?.upstreamShortName, headBranch?.upstreamRemoteName == remote {
            return String(upstream.dropFirst(remote.count + 1))
        }
        return head
    }

    var headCandidates: [String] {
        refs.localBranches.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Branches on the remote, which is all a host can merge into.
    var baseCandidates: [String] {
        let prefix = remote + "/"
        let names = refs.remoteBranches.filter { $0.remoteName == remote && $0.name != prefix + "HEAD" }
            .map { String($0.name.dropFirst(prefix.count)) }
        let all = names.contains(base) || base.isEmpty ? names : names + [base]
        return all.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var publishState: BranchPublishState { BranchPublishState(branch: headBranch) }

    var isSubmitting: Bool { progressTitle != nil }

    var canSubmit: Bool {
        !isSubmitting && !refs.remotes.isEmpty && !head.isEmpty && !base.isEmpty && remoteHead != base
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var draft: PullRequestDraft {
        PullRequestDraft(base: base, head: remoteHead, title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                         body: body, isDraft: isDraft, reviewers: PullRequestDraft.reviewers(from: reviewersText))
    }

    // MARK: Loading

    /// Picks the base (the branch the head is stacked on, else the remote's default branch), then prefills from commits.
    func load() async {
        if !refs.hasLoaded { await refs.loadIfNeeded() }
        let remoteDefault = await repository.defaultBranch(of: remote)
        // Sitting on the default branch, the change to propose is on some other branch without a pull request.
        if !isHeadExplicit, head == remoteDefault,
           let other = headCandidates.first(where: { $0 != head && !refs.hasOpenPullRequest(branch: $0) }) {
            head = other
        }
        let candidates = baseCandidates.filter { $0 != remoteHead }
        if let parent = refs.stack(containing: head)?.layer(head)?.parent, candidates.contains(parent) {
            base = parent
        } else {
            base = PullRequestDraft.defaultBase(remoteHead: remoteDefault, candidates: candidates) ?? ""
        }
        await loadCommits()
    }

    private func loadCommits() async {
        guard !head.isEmpty, !base.isEmpty else { commits = []; return }
        let (head, base) = (head, base)
        isLoadingCommits = true
        defer { isLoadingCommits = false }
        let baseRef = refs.remoteBranches.contains { $0.name == "\(remote)/\(base)" } ? "\(remote)/\(base)" : base
        let loaded = (try? await repository.log(maxCount: 250, skip: 0, revisions: [head, "^\(baseRef)"])) ?? []
        // The picker may have moved on while git ran.
        guard head == self.head, base == self.base else { return }
        commits = loaded
        let prefill = PullRequestDraft.prefill(head: head, commits: loaded)
        if !isTitleEdited { title = prefill.title }
        if !isBodyEdited { body = prefill.body }
    }

    // MARK: Editing

    func setHead(_ name: String) async {
        guard name != head else { return }
        head = name
        await loadCommits()
    }

    func setBase(_ name: String) async {
        guard name != base else { return }
        base = name
        await loadCommits()
    }

    // Fields echo their current value on focus; only a real change counts as an edit.
    func setTitle(_ text: String) {
        guard text != title else { return }
        title = text
        isTitleEdited = true
    }

    func setBody(_ text: String) {
        guard text != body else { return }
        body = text
        isBodyEdited = true
    }

    func setReviewers(_ text: String) { reviewersText = text }

    func setDraft(_ draft: Bool) { isDraft = draft }

    // MARK: Submitting

    /// A head the host can't see yet is pushed first, after the user confirms.
    func submit() async {
        guard canSubmit else { return }
        if publishState.needsPush {
            isConfirmingPush = true
        } else {
            await create()
        }
    }

    func cancelPush() { isConfirmingPush = false }

    func confirmPush() async {
        isConfirmingPush = false
        errorMessage = nil
        progressTitle = "Pushing \(head) to \(remote)…"
        do {
            try await repository.publishBranch(head, to: remote, as: remoteHead)
        } catch {
            progressTitle = nil
            errorMessage = error.localizedDescription
            return
        }
        await create()
    }

    private func create() async {
        errorMessage = nil
        progressTitle = "Creating pull request…"
        do {
            let url = try await repository.createPullRequest(draft)
            progressTitle = nil
            await onCreated?(url)
        } catch {
            progressTitle = nil
            errorMessage = error.localizedDescription
        }
    }
}
