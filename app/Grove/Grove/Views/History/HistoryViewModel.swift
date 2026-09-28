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
    private(set) var branches: [BranchInfo] = [] {
        didSet { branchesBySHA = Self.index(branches) }
    }
    private(set) var tags: [TagInfo] = [] {
        didSet { tagsBySHA = Dictionary(grouping: tags, by: \.targetSHA) }
    }
    // Rows look refs up by SHA; scanning thousands of tags per row per render made branch switches slow.
    private var branchesBySHA: [String: [BranchInfo]] = [:]
    /// Signature state of the selected commit; nil until verified.
    private(set) var selectedSignature: SignatureStatus?
    private var tagsBySHA: [String: [TagInfo]] = [:]
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
    private var prefetchTask: Task<Void, Never>?
    // Keyed by SHA: a commit's diff, tree and signature never change, so revisits skip git entirely.
    @ObservationIgnored private var detailCache = LRUCache<String, CommitDetails>(capacity: 50)

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
        // Refs only decorate rows, so the log doesn't wait for them.
        async let refs: Void = loadRefs()
        await loadMore()
        if selectedCommit == nil, let first = commits.first { select(first) }
        await refs
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
        branchesBySHA[commit.id] ?? []
    }

    func tags(at commit: CommitInfo) -> [TagInfo] {
        tagsBySHA[commit.id] ?? []
    }

    /// HEAD first, then local, then remote branches; `origin/HEAD` aliases are dropped.
    private static func index(_ branches: [BranchInfo]) -> [String: [BranchInfo]] {
        Dictionary(grouping: branches.filter { !$0.id.hasSuffix("/HEAD") }, by: \.targetSHA)
            .mapValues { $0.sorted { ($0.isHEAD ? 0 : $0.isLocal ? 1 : 2) < ($1.isHEAD ? 0 : $1.isLocal ? 1 : 2) } }
    }

    func commit(withID id: String) -> CommitInfo? {
        commits.first { $0.id == id }
    }

    // MARK: - Selection

    func select(_ commit: CommitInfo) {
        guard selectedCommit?.id != commit.id else { return }
        detailTask?.cancel()
        selectedCommit = commit
        // A cached commit shows at once; a miss starts from a clean loading state, never the previous commit.
        let cached = detailCache.value(for: commit.id)
        commitDiffs = cached?.diffs ?? []
        expandedPaths = Self.defaultExpanded(commitDiffs)
        treeFiles = cached?.tree ?? []
        selectedSignature = cached?.signature
        isLoadingDiff = cached?.diffs == nil
        isLoadingTree = false
        guard cached?.isComplete(needsTree: detailTab == .tree) != true else { return }
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
        let next = index + (offset < 0 ? -1 : 1)
        if visible.indices.contains(next) { prefetchDiff(for: visible[next]) }
    }

    private func clearSelection() {
        detailTask?.cancel()
        selectedCommit = nil
        commitDiffs = []
        expandedPaths = []
        treeFiles = []
        selectedSignature = nil
        isLoadingDiff = false
    }

    private func loadDetails(for commit: CommitInfo) async {
        let cached = detailCache.peek(commit.id)
        // Verifying a signature is slow, so only the selected commit is checked, alongside its diff.
        let needsSignature = cached?.signature == nil
        async let verified: CommitInfo? = needsSignature ? try? repository.commitDetail(commit.id) : nil
        if cached?.diffs == nil {
            do {
                let diffs = try await repository.diffForCommit(commit.id)
                detailCache.update(commit.id, default: CommitDetails()) { $0.diffs = diffs }
                // A newer selection may have started while this diff was loading.
                guard selectedCommit?.id == commit.id else { return }
                commitDiffs = diffs
                expandedPaths = Self.defaultExpanded(diffs)
            } catch {
                if selectedCommit?.id == commit.id { errorMessage = error.localizedDescription }
            }
            guard selectedCommit?.id == commit.id else { return }
            isLoadingDiff = false
        }
        if detailTab == .tree, treeFiles.isEmpty { await loadTree() }
        if let isSigned = await verified?.isSigned {
            let signature: SignatureStatus = isSigned ? .verified : .unsigned
            detailCache.update(commit.id, default: CommitDetails()) { $0.signature = signature }
            if selectedCommit?.id == commit.id { selectedSignature = signature }
        }
    }

    /// Warms the diff of the commit the arrow keys will land on next; debounced so held keys don't pile up git calls.
    private func prefetchDiff(for commit: CommitInfo) {
        prefetchTask?.cancel()
        guard detailCache.peek(commit.id)?.diffs == nil else { return }
        prefetchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, detailCache.peek(commit.id)?.diffs == nil,
                  let diffs = try? await repository.diffForCommit(commit.id) else { return }
            detailCache.update(commit.id, default: CommitDetails()) { $0.diffs = diffs }
        }
    }

    private static func defaultExpanded(_ diffs: [FileDiff]) -> Set<String> {
        diffs.count == 1 ? Set(diffs.map(\.path)) : []
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
        if let tree = detailCache.value(for: commit.id)?.tree {
            treeFiles = tree
            return
        }
        isLoadingTree = true
        defer { if selectedCommit?.id == commit.id { isLoadingTree = false } }
        do {
            let files = try await repository.filesInCommit(commit.id)
            detailCache.update(commit.id, default: CommitDetails()) { $0.tree = files }
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

/// Everything the detail pane shows for one commit; each part fills in as it loads.
struct CommitDetails {
    var diffs: [FileDiff]?
    var tree: [String]?
    var signature: SignatureStatus?

    func isComplete(needsTree: Bool) -> Bool {
        diffs != nil && signature != nil && (!needsTree || tree != nil)
    }
}
