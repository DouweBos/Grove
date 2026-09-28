// Views/PullRequests/PullRequestsViewModel.swift
// Grove

import Foundation
import Observation

enum PRFilterState: String, CaseIterable, Hashable {
    case open = "Open"
    case closed = "Closed"
    case all = "All"
}

enum PRDetailTab: String, CaseIterable, Hashable {
    case overview = "Overview"
    case commits = "Commits"
    case files = "Files"
}

/// Why the list couldn't load, so the view can offer the right fix.
enum PRLoadFailure: Equatable {
    case ghMissing
    case notAuthenticated
    case noGitHubRemote
    case other(String)

    init(_ error: Error) {
        let text = error.localizedDescription
        if case GitHubCLI.Failure.notInstalled = error { self = .ghMissing; return }
        if case GitHubCLI.Failure.notAuthenticated = error { self = .notAuthenticated; return }
        if !GitHubCLI.isInstalled { self = .ghMissing; return }
        if text.contains("gh auth login") || text.contains("not logged") { self = .notAuthenticated; return }
        if text.contains("known GitHub host") || text.contains("no git remotes") { self = .noGitHubRemote; return }
        self = .other(text)
    }
}

@MainActor
@Observable
final class PullRequestsViewModel {

    enum Operation: String { case merge, close }

    struct PendingOperation: Identifiable {
        let operation: Operation
        let pr: PullRequestInfo
        var id: String { "\(operation.rawValue)-\(pr.id)" }
    }

    // MARK: - List State

    private(set) var pullRequests: [PullRequestInfo] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var loadFailure: PRLoadFailure?
    private(set) var filterState: PRFilterState = .open
    private(set) var searchText = ""

    // MARK: - Detail State

    private(set) var selectedPR: PullRequestInfo?
    private(set) var activeDetailTab: PRDetailTab = .overview
    private(set) var comments: [PRComment] = []
    private(set) var reviewThreads: [PRReviewThread] = []
    private(set) var commentDraft = ""
    private(set) var isPostingComment = false
    private(set) var commentError: String?
    private(set) var isLoadingComments = false
    private(set) var prCommits: [CommitInfo] = []
    private(set) var isLoadingPRCommits = false
    private(set) var prChangeset: [FileDiff] = []
    private(set) var selectedChangesetPath: String?
    private(set) var isLoadingChangeset = false
    /// A cached PR is on screen while its details are re-fetched from GitHub.
    private(set) var isRevalidating = false
    // Keyed by number and updatedAt, so an edited PR misses instead of showing its old state.
    @ObservationIgnored private var detailCache = LRUCache<PRDetailKey, PRDetails>(capacity: 30)

    var actionError: String?
    var pendingOperation: PendingOperation?
    private(set) var isPerforming = false

    /// The open "Create Pull Request" sheet.
    private(set) var creation: CreatePullRequestViewModel?

    var onRepositoryChanged: (() async -> Void)?
    /// Set by the session: brings the Pull Requests tab up, e.g. after creating one from the sidebar.
    var onShowPullRequests: (() -> Void)?

    let repository: any GitRepositoryProtocol
    let refs: RepositoryRefs

    init(repository: any GitRepositoryProtocol, refs: RepositoryRefs? = nil) {
        self.repository = repository
        self.refs = refs ?? RepositoryRefs(repository: repository)
    }

    // MARK: - Derived

    var filteredPullRequests: [PullRequestInfo] {
        let byState = pullRequests.filter { matches($0, filterState) }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return byState }
        return byState.filter {
            $0.title.lowercased().contains(query) || "#\($0.id)".contains(query)
                || $0.authorName.lowercased().contains(query) || $0.sourceBranch.lowercased().contains(query)
        }
    }

    func count(for filter: PRFilterState) -> Int {
        pullRequests.filter { matches($0, filter) }.count
    }

    private func matches(_ pr: PullRequestInfo, _ filter: PRFilterState) -> Bool {
        switch filter {
        case .open: pr.state == .open
        case .closed: pr.state != .open
        case .all: true
        }
    }

    // MARK: - Loading

    func refresh() async {
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            pullRequests = try await repository.pullRequests()
            loadFailure = nil
            if let selected = selectedPR {
                selectedPR = pullRequests.first { $0.id == selected.id }
                if let updated = selectedPR, updated.updatedDate != selected.updatedDate {
                    await revalidateEdited(from: selected, to: updated)
                }
            }
            if selectedPR == nil, let first = filteredPullRequests.first {
                await select(first)
            }
        } catch {
            loadFailure = PRLoadFailure(error)
        }
    }

    func setFilter(_ filter: PRFilterState) {
        filterState = filter
    }

    func setSearchText(_ text: String) {
        searchText = text
    }

    func select(_ pr: PullRequestInfo) async {
        guard pr.id != selectedPR?.id else { return }
        selectedPR = pr
        let cached = detailCache.value(for: PRDetailKey(pr))
        comments = cached?.comments ?? []
        reviewThreads = cached?.reviewThreads ?? []
        commentError = nil
        prCommits = cached?.commits ?? []
        prChangeset = cached?.changeset ?? []
        selectedChangesetPath = prChangeset.first?.path
        isLoadingComments = false
        isLoadingPRCommits = false
        isLoadingChangeset = false
        isRevalidating = false
        if cached == nil {
            await loadTabContent()
            await loadComments(for: pr)
        } else {
            await revalidate(pr)
        }
    }

    func selectTab(_ tab: PRDetailTab) async {
        activeDetailTab = tab
        await loadTabContent()
    }

    func selectChangesetFile(_ file: FileDiff) {
        selectedChangesetPath = file.path
    }

    /// Re-fetches what the cache already showed; the small header spinner replaces full-pane loading.
    private func revalidate(_ pr: PullRequestInfo) async {
        isRevalidating = true
        defer { if selectedPR?.id == pr.id { isRevalidating = false } }
        await loadTabContent(force: true)
        await loadComments(for: pr)
    }

    /// The same PR changed on GitHub: keep its old details up under the small spinner until the new ones land.
    private func revalidateEdited(from old: PullRequestInfo, to new: PullRequestInfo) async {
        if let previous = detailCache.peek(PRDetailKey(old)) {
            detailCache.removeValue(for: PRDetailKey(old))
            detailCache.insert(previous, for: PRDetailKey(new))
        }
        await revalidate(new)
    }

    private func loadComments(for pr: PullRequestInfo) async {
        let key = PRDetailKey(pr)
        let showSpinner = detailCache.peek(key)?.comments == nil
        if showSpinner { isLoadingComments = true }
        defer { if selectedPR?.id == pr.id { isLoadingComments = false } }
        async let conversation = try? repository.pullRequestComments(number: pr.id)
        async let review = try? repository.pullRequestReviewComments(number: pr.id)
        let (loaded, lineComments) = await (conversation, review)
        let threads = lineComments.map(PRReviewThread.threads(from:))
        if let loaded { detailCache.update(key, default: PRDetails()) { $0.comments = loaded } }
        if let threads { detailCache.update(key, default: PRDetails()) { $0.reviewThreads = threads } }
        guard selectedPR?.id == pr.id else { return }
        if let loaded { comments = loaded }
        if let threads { reviewThreads = threads }
    }

    // MARK: - Commenting

    func setCommentDraft(_ text: String) {
        commentDraft = text
    }

    var canPostComment: Bool {
        selectedPR != nil && !isPostingComment && !commentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Posts the draft on the selected pull request, then re-reads its conversation.
    func postComment() async {
        guard canPostComment, let pr = selectedPR else { return }
        isPostingComment = true
        commentError = nil
        defer { isPostingComment = false }
        do {
            try await repository.commentOnPullRequest(number: pr.id, body: commentDraft.trimmingCharacters(in: .whitespacesAndNewlines))
            commentDraft = ""
            await loadComments(for: pr)
        } catch {
            commentError = error.localizedDescription
        }
    }

    private func loadTabContent(force: Bool = false) async {
        guard let pr = selectedPR else { return }
        let cached = detailCache.peek(PRDetailKey(pr))
        switch activeDetailTab {
        case .overview: break
        case .commits where force || cached?.commits == nil: await loadCommits(for: pr)
        case .files where force || cached?.changeset == nil: await loadChangeset(for: pr)
        default: break
        }
    }

    private func loadCommits(for pr: PullRequestInfo) async {
        let key = PRDetailKey(pr)
        if detailCache.peek(key)?.commits == nil { isLoadingPRCommits = true }
        defer { if selectedPR?.id == pr.id { isLoadingPRCommits = false } }
        guard let commits = try? await repository.pullRequestCommits(number: pr.id) else { return }
        detailCache.update(key, default: PRDetails()) { $0.commits = commits }
        if selectedPR?.id == pr.id { prCommits = commits }
    }

    private func loadChangeset(for pr: PullRequestInfo) async {
        let key = PRDetailKey(pr)
        if detailCache.peek(key)?.changeset == nil { isLoadingChangeset = true }
        defer { if selectedPR?.id == pr.id { isLoadingChangeset = false } }
        do {
            let files = try await repository.pullRequestDiff(number: pr.id)
            detailCache.update(key, default: PRDetails()) { $0.changeset = files }
            guard selectedPR?.id == pr.id else { return }
            prChangeset = files
            if !files.contains(where: { $0.path == selectedChangesetPath }) { selectedChangesetPath = files.first?.path }
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Actions

    func checkout(_ pr: PullRequestInfo) async {
        await perform { try await self.repository.checkoutPullRequest(number: pr.id) }
    }

    func openInBrowser(_ pr: PullRequestInfo) {
        let path = repository.path
        Task {
            do { _ = try await GitHubCLI.run(["pr", "view", "\(pr.id)", "--web"], in: path) } catch {
                actionError = error.localizedDescription
            }
        }
    }

    func request(_ operation: Operation, on pr: PullRequestInfo) {
        pendingOperation = PendingOperation(operation: operation, pr: pr)
    }

    func cancelPendingOperation() {
        pendingOperation = nil
    }

    /// Takes the dialog item because the dialog clears `pendingOperation` before running its action.
    func confirm(_ pending: PendingOperation) async {
        pendingOperation = nil
        switch pending.operation {
        case .merge: await perform { try await self.repository.mergePullRequest(number: pending.pr.id) }
        case .close: await perform { try await self.repository.closePullRequest(number: pending.pr.id) }
        }
        await refresh()
    }

    // MARK: - Creating

    /// Opens the sheet with `head` (the checked-out branch when nil) as the branch to merge.
    func beginCreatePullRequest(head: String? = nil) {
        let creation = CreatePullRequestViewModel(repository: repository, refs: refs, head: head)
        creation.onCreated = { [weak self] url in await self?.didCreatePullRequest(url: url) }
        self.creation = creation
    }

    func cancelCreatePullRequest() {
        creation = nil
    }

    private func didCreatePullRequest(url: String) async {
        creation = nil
        onShowPullRequests?()
        // The head may have just been pushed, and its branch row should show the new number.
        await onRepositoryChanged?()
        refs.refreshPullRequests(force: true)
        filterState = .open
        await refresh()
        if let number = PullRequestDraft.number(fromURL: url), let created = pullRequests.first(where: { $0.id == number }) {
            await select(created)
        }
    }

    func clearActionError() {
        actionError = nil
    }

    private func perform(_ work: @escaping () async throws -> Void) async {
        isPerforming = true
        defer { isPerforming = false }
        do {
            try await work()
            await onRepositoryChanged?()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

/// Identity of a pull request's detail content; `updatedAt` moves whenever GitHub sees a change.
struct PRDetailKey: Hashable {
    let number: Int
    let updated: Date

    init(_ pr: PullRequestInfo) {
        number = pr.id
        updated = pr.updatedDate
    }
}

/// Detail tabs of one pull request; each fills in when its tab is first shown.
struct PRDetails {
    var comments: [PRComment]?
    var reviewThreads: [PRReviewThread]?
    var commits: [CommitInfo]?
    var changeset: [FileDiff]?
}
