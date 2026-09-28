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
    private(set) var isLoadingComments = false
    private(set) var prCommits: [CommitInfo] = []
    private(set) var isLoadingPRCommits = false
    private(set) var prChangeset: [FileDiff] = []
    private(set) var selectedChangesetPath: String?
    private(set) var isLoadingChangeset = false
    private var loadedCommitsFor: Int?
    private var loadedChangesetFor: Int?

    var actionError: String?
    var pendingOperation: PendingOperation?
    private(set) var isPerforming = false

    var onRepositoryChanged: (() async -> Void)?

    let repository: any GitRepositoryProtocol

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
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
        comments = []
        prCommits = []
        prChangeset = []
        selectedChangesetPath = nil
        loadedCommitsFor = nil
        loadedChangesetFor = nil
        await loadTabContent()
        isLoadingComments = true
        defer { isLoadingComments = false }
        let loaded = (try? await repository.pullRequestComments(number: pr.id)) ?? []
        if selectedPR?.id == pr.id { comments = loaded }
    }

    func selectTab(_ tab: PRDetailTab) async {
        activeDetailTab = tab
        await loadTabContent()
    }

    func selectChangesetFile(_ file: FileDiff) {
        selectedChangesetPath = file.path
    }

    private func loadTabContent() async {
        guard let pr = selectedPR else { return }
        switch activeDetailTab {
        case .overview:
            break
        case .commits where loadedCommitsFor != pr.id:
            loadedCommitsFor = pr.id
            isLoadingPRCommits = true
            defer { isLoadingPRCommits = false }
            let commits = (try? await repository.pullRequestCommits(number: pr.id)) ?? []
            if selectedPR?.id == pr.id { prCommits = commits }
        case .files where loadedChangesetFor != pr.id:
            loadedChangesetFor = pr.id
            isLoadingChangeset = true
            defer { isLoadingChangeset = false }
            do {
                let files = try await repository.pullRequestDiff(number: pr.id)
                guard selectedPR?.id == pr.id else { return }
                prChangeset = files
                selectedChangesetPath = files.first?.path
            } catch {
                actionError = error.localizedDescription
            }
        default:
            break
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
