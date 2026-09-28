// Views/History/HistoryViewModel.swift
// Grove

import Foundation
import Observation

/// Commit log, graph, selection and commit actions for the History tab.
@MainActor
@Observable
final class HistoryViewModel {

    enum DetailTab: String, CaseIterable, Identifiable {
        case changeset = "Changeset"
        case tree = "Tree"
        var id: Self { self }
    }

    // MARK: - Log

    private(set) var commits: [CommitInfo] = []
    private(set) var branches: [BranchInfo] = []
    private(set) var tags: [TagInfo] = []
    private(set) var graphNodes: [String: GraphNode] = [:]
    private(set) var maxGraphColumns = 1
    private(set) var isLoading = false
    private(set) var hasMore = true
    private(set) var searchText = ""
    var filterBranch: String?
    var errorMessage: String?

    // MARK: - Detail

    private(set) var selectedCommit: CommitInfo?
    private(set) var commitDiffs: [FileDiff] = []
    private(set) var expandedPaths: Set<String> = []
    private(set) var isLoadingDiff = false
    private(set) var detailTab: DetailTab = .changeset
    private(set) var treeFiles: [String] = []
    private(set) var isLoadingTree = false

    // MARK: - Actions

    private(set) var pendingAction: HistoryAction?
    private(set) var isPerformingAction = false
    /// Set by the session so mutations refresh every view, not just this list.
    var onRepositoryChanged: (() async -> Void)?
    var undoManager: GitUndoManager?

    let repository: any GitRepositoryProtocol
    private let pageSize = 100
    private var hasLoaded = false
    private var detailTask: Task<Void, Never>?

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // Setters for the actions extension, which lives in its own file.
    func setPendingAction(_ action: HistoryAction?) { pendingAction = action }
    func setPerforming(_ performing: Bool) { isPerformingAction = performing }

    // MARK: - Loading

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await loadInitial()
    }

    func loadInitial() async {
        hasLoaded = true
        commits = []
        hasMore = true
        graphNodes = [:]
        await loadRefs()
        await loadMore()
        if selectedCommit == nil, let first = commits.first { select(first) }
    }

    /// Re-reads the loaded range in place, keeping the selection, after the repository changes.
    func reload() async {
        guard hasLoaded, !isLoading else { return }
        await loadRefs()
        isLoading = true
        defer { isLoading = false }
        do {
            let count = max(commits.count, pageSize)
            let page = try await repository.log(maxCount: count, skip: 0, branch: filterBranch)
            guard page.map(\.id) != commits.map(\.id) else { return }
            commits = page
            hasMore = page.count == count
            buildGraph()
            if let selected = selectedCommit, !page.contains(where: { $0.id == selected.id }) {
                clearSelection()
                if let first = page.first { select(first) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadMore() async {
        guard hasMore, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await repository.log(maxCount: pageSize, skip: commits.count, branch: filterBranch)
            commits.append(contentsOf: page)
            hasMore = page.count == pageSize
            buildGraph()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Pages in more history once the list scrolls to its last row.
    func rowAppeared(_ commit: CommitInfo) {
        guard commit.id == filteredCommits.last?.id else { return }
        Task { await loadMore() }
    }

    private func loadRefs() async {
        do {
            async let local = repository.localBranches()
            async let remote = repository.remoteBranches()
            async let tagList = repository.tags()
            let (l, r, t) = try await (local, remote, tagList)
            branches = l + r
            tags = t
        } catch {
            // Refs only decorate rows; the log is still usable without them.
        }
    }

    // MARK: - Filter

    func setSearchText(_ text: String) {
        searchText = text
    }

    var filteredCommits: [CommitInfo] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return commits }
        return commits.filter {
            $0.id.hasPrefix(query)
                || $0.message.lowercased().contains(query)
                || $0.authorName.lowercased().contains(query)
                || $0.authorEmail.lowercased().contains(query)
        }
    }

    var isFiltering: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Refs

    /// HEAD is the tip of the unfiltered log; branch views look it up from the refs.
    var headSHA: String? {
        filterBranch == nil ? commits.first?.id : branches.first(where: \.isHEAD)?.targetSHA
    }

    var headBranchName: String? { branches.first(where: \.isHEAD)?.name }

    func branches(at commit: CommitInfo) -> [BranchInfo] {
        branches.filter { $0.targetSHA == commit.id && !$0.id.hasSuffix("/HEAD") }
            .sorted { ($0.isHEAD ? 0 : $0.isLocal ? 1 : 2) < ($1.isHEAD ? 0 : $1.isLocal ? 1 : 2) }
    }

    func tags(at commit: CommitInfo) -> [TagInfo] {
        // Tag refs carry abbreviated SHAs.
        tags.filter { !$0.targetSHA.isEmpty && commit.id.hasPrefix($0.targetSHA) }
    }

    func commit(withID id: String) -> CommitInfo? {
        commits.first { $0.id == id }
    }

    // MARK: - Selection

    func select(_ commit: CommitInfo) {
        guard selectedCommit?.id != commit.id else { return }
        selectedCommit = commit
        commitDiffs = []
        expandedPaths = []
        treeFiles = []
        detailTask?.cancel()
        detailTask = Task { await loadDetails(for: commit) }
    }

    /// Selects a parent SHA from the detail header, paging it in if needed.
    func selectCommit(id: String) async {
        while commit(withID: id) == nil, hasMore {
            let before = commits.count
            await loadMore()
            if commits.count == before { break }
        }
        if let commit = commit(withID: id) {
            setSearchText("")
            select(commit)
        }
    }

    /// Arrow-key navigation through the visible (filtered) list.
    func selectAdjacent(offset: Int) {
        let visible = filteredCommits
        guard !visible.isEmpty else { return }
        let current = selectedCommit.flatMap { sel in visible.firstIndex { $0.id == sel.id } }
        let index = min(max((current ?? -1) + offset, 0), visible.count - 1)
        select(visible[index])
    }

    private func clearSelection() {
        detailTask?.cancel()
        selectedCommit = nil
        commitDiffs = []
        expandedPaths = []
        treeFiles = []
    }

    private func loadDetails(for commit: CommitInfo) async {
        isLoadingDiff = true
        do {
            let diffs = try await repository.diffForCommit(commit.id)
            // A newer selection may have started while this diff was loading.
            guard selectedCommit?.id == commit.id else { return }
            commitDiffs = diffs
            if diffs.count == 1, let only = diffs.first { expandedPaths = [only.path] }
        } catch {
            if selectedCommit?.id == commit.id { errorMessage = error.localizedDescription }
        }
        if selectedCommit?.id == commit.id {
            isLoadingDiff = false
            if detailTab == .tree { await loadTree() }
        }
    }

    // MARK: - Detail

    func selectDetailTab(_ tab: DetailTab) {
        detailTab = tab
        if tab == .tree, treeFiles.isEmpty { Task { await loadTree() } }
    }

    func toggleFile(_ path: String) {
        if expandedPaths.contains(path) { expandedPaths.remove(path) } else { expandedPaths.insert(path) }
    }

    func setAllFilesExpanded(_ expanded: Bool) {
        expandedPaths = expanded ? Set(commitDiffs.map(\.path)) : []
    }

    /// Shows a file from the tree in the changeset tab, expanded.
    func revealInChangeset(_ path: String) {
        expandedPaths.insert(path)
        detailTab = .changeset
    }

    func fileDiff(for path: String) -> FileDiff? {
        commitDiffs.first { $0.path == path }
    }

    private func loadTree() async {
        guard let commit = selectedCommit else { return }
        isLoadingTree = true
        defer { if selectedCommit?.id == commit.id { isLoadingTree = false } }
        do {
            let files = try await repository.filesInCommit(commit.id)
            guard selectedCommit?.id == commit.id else { return }
            treeFiles = files
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Graph

    private func buildGraph() {
        let nodes = CommitGraphBuilder().buildGraph(from: commits)
        graphNodes = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let widest = nodes.flatMap { node in node.lines.map { max($0.fromColumn, $0.toColumn) } + [node.column] }.max() ?? 0
        maxGraphColumns = widest + 1
    }
}
