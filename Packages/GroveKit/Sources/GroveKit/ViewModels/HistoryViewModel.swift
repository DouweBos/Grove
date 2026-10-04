// ViewModels/HistoryViewModel.swift
// GroveKit

import Foundation
import Observation

/// Commit log, graph, selection and commit actions for the History tab.
@MainActor
@Observable
public final class HistoryViewModel {

    public enum DetailTab: String, CaseIterable, Identifiable {
        case changeset = "Changeset"
        case tree = "Tree"
        public var id: Self { self }
    }

    // MARK: - Log

    public private(set) var commits: [CommitInfo] = []
    public private(set) var branches: [BranchInfo] = [] {
        didSet { branchesBySHA = Self.index(branches) }
    }
    public private(set) var tags: [TagInfo] = [] {
        didSet { tagsBySHA = Dictionary(grouping: tags, by: \.targetSHA) }
    }
    // Rows look refs up by SHA; scanning thousands of tags per row per render made branch switches slow.
    private var branchesBySHA: [String: [BranchInfo]] = [:]
    /// Signature state of the selected commit; nil until verified.
    public private(set) var selectedSignature: SignatureStatus?
    private var tagsBySHA: [String: [TagInfo]] = [:]
    public private(set) var graphNodes: [String: GraphNode] = [:]
    public private(set) var maxGraphColumns = 1
    @ObservationIgnored private var graphBuilder = CommitGraphBuilder()
    public private(set) var isLoading = false {
        didSet { if !isLoading, pendingReload { Task { await reloadLog() } } }
    }
    public private(set) var hasMore = true
    public private(set) var searchText = ""
    public var filterBranch: String?
    public var errorMessage: String?
    /// The shown branch's upstream, logged alongside it so commits waiting to be pulled appear too.
    public private(set) var upstreamName: String?
    /// Commits on the upstream the branch doesn't have yet.
    private(set) var incomingSHAs: Set<String> = []
    /// Commits on the branch the upstream doesn't have yet.
    private(set) var outgoingSHAs: Set<String> = []
    private var revisions: [String] = []
    private var syncStateTask: Task<Void, Never>?

    // MARK: - Detail

    /// Selected commit SHAs; the focused one is ``selectedCommit``.
    public private(set) var selection = ListSelection<String>()
    public private(set) var selectedCommit: CommitInfo?
    public private(set) var commitDiffs: [FileDiff] = []
    public private(set) var expandedPaths: Set<String> = []
    public private(set) var isLoadingDiff = false
    public private(set) var detailTab: DetailTab = .changeset
    /// Shared by every window through the app preference.
    public private(set) var layout = ViewModelPreferences.historyLayout
    public private(set) var treeFiles: [String] = []
    public private(set) var isLoadingTree = false

    // MARK: - Actions

    public private(set) var pendingAction: HistoryAction?
    public private(set) var isPerformingAction = false
    /// Set by the session so mutations refresh every view, not just this list.
    public var onRepositoryChanged: (() async -> Void)?
    /// Reports each action this view model runs, e.g. to the app's telemetry.
    @ObservationIgnored public var onAction: GroveKitActionHandler?
    /// Set by the session to show Changes, where the conflict banner continues a stopped rebase.
    public var onRebaseStopped: (() -> Void)?
    public var undoManager: GitUndoManager?

    public let repository: any GitRepositoryProtocol
    /// The session's shared refs; rows decorate from them instead of reading refs per list.
    public let refs: RepositoryRefs
    private let pageSize = 100
    private var hasLoaded = false
    /// Set while hidden during a repository change, so the next appearance reloads.
    public private(set) var isStale = false
    /// A reload asked for while the log was loading; it runs once that finishes.
    private var pendingReload = false
    private var appliedRefsGeneration: Int?
    private var detailTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    // Keyed by SHA: a commit's diff, tree and signature never change, so revisits skip git entirely.
    @ObservationIgnored private var detailCache = LRUCache<String, CommitDetails>(capacity: 50)

    public init(repository: any GitRepositoryProtocol, refs: RepositoryRefs? = nil) {
        self.repository = repository
        self.refs = refs ?? RepositoryRefs(repository: repository)
    }

    // Setters for the actions extension, which lives in its own file.
    func setPendingAction(_ action: HistoryAction?) { pendingAction = action }
    func setPerforming(_ performing: Bool) { isPerformingAction = performing }

    // MARK: - Loading

    public func loadIfNeeded() async {
        guard hasLoaded else { return await loadInitial() }
        guard isStale else { return }
        isStale = false
        syncRefs()
        await reloadLog()
    }

    /// The repository changed while this list was hidden; it reloads when shown again.
    public func markStale() {
        if hasLoaded { isStale = true }
    }

    public func loadInitial() async {
        hasLoaded = true
        isStale = false
        commits = []
        hasMore = true
        buildGraph()
        if refs.hasLoaded { syncRefs() } else { updateRevisions() }
        // Refs only decorate rows, so the log doesn't wait for them.
        async let refs = loadRefs()
        await loadMore()
        if selectedCommit == nil, let first = commits.first { select(first) }
        // The refs can reveal an upstream to log alongside the branch.
        if await refs { await reloadLog() }
    }

    /// Re-reads the loaded range in place, keeping the selection, after the repository changes.
    /// Joins the session's ref read when one is already running.
    public func reload() async {
        guard hasLoaded else { return }
        isStale = false
        async let refsRead: Void = refs.refresh()
        await reloadLog()
        await refsRead
        if syncRefs() { await reloadLog() }
    }

    private func reloadLog() async {
        guard !isLoading else { return pendingReload = true }
        pendingReload = false
        isLoading = true
        defer { isLoading = false }
        do {
            let count = max(commits.count, pageSize)
            let page = try await repository.log(maxCount: count, skip: 0, revisions: revisions)
            guard page.map(\.id) != commits.map(\.id) else { return }
            commits = page
            hasMore = page.count == count
            buildGraph()
            let loaded = Set(page.map(\.id))
            var kept = selection
            kept.reconcile { loaded.contains($0) ? $0 : nil }
            if kept.focus == nil, let first = page.first { kept.select(first.id) }
            applySelection(kept)
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
            let page = try await repository.log(maxCount: pageSize, skip: commits.count, revisions: revisions)
            commits.append(contentsOf: page)
            hasMore = page.count == pageSize
            appendGraph(page)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Pages in more history once the list scrolls to its last row.
    public func rowAppeared(_ commit: CommitInfo) {
        guard commit.id == filteredCommits.last?.id else { return }
        Task { await loadMore() }
    }

    private func loadRefs() async -> Bool {
        await refs.loadIfNeeded()
        return syncRefs()
    }

    /// Re-indexes only when the shared refs actually changed; thousands of tags make that costly.
    /// Returns whether the log's revisions changed, so the caller reloads it.
    @discardableResult
    func syncRefs() -> Bool {
        guard appliedRefsGeneration != refs.generation else { return false }
        appliedRefsGeneration = refs.generation
        branches = refs.localBranches + refs.remoteBranches
        tags = refs.tags
        let revisionsChanged = updateRevisions()
        loadSyncState()
        return revisionsChanged
    }

    /// Whether the revisions to log changed, e.g. once refs reveal the branch's upstream.
    @discardableResult
    private func updateRevisions() -> Bool {
        let branch = trackedBranch
        let upstream = branch?.upstream.flatMap { ref in refs.remoteBranches.first { $0.id == ref } }
        upstreamName = upstream?.name
        let base = filterBranch.map { [$0] } ?? (upstream == nil ? [] : ["HEAD"])
        let next = base + (upstream.map { [$0.id] } ?? [])
        guard next != revisions else { return false }
        revisions = next
        return true
    }

    /// What the log lists; HEAD until refs reveal an upstream to show beside it.
    var logRevisions: [String] { revisions.isEmpty ? ["HEAD"] : revisions }

    /// The local branch whose history this is: the filter, or the checked-out branch.
    private var trackedBranch: BranchInfo? {
        guard let name = filterBranch ?? headBranchName else { return nil }
        return refs.localBranches.first { $0.name == name }
    }

    private func loadSyncState() {
        syncStateTask?.cancel()
        guard let branch = trackedBranch, let upstream = branch.upstream, upstreamName != nil else {
            incomingSHAs = []
            outgoingSHAs = []
            return
        }
        syncStateTask = Task {
            async let incoming = branch.behind > 0 ? try? repository.commits(in: upstream, notIn: branch.id) : nil
            async let outgoing = branch.ahead > 0 ? try? repository.commits(in: branch.id, notIn: upstream) : nil
            let (behind, ahead) = await (incoming ?? [], outgoing ?? [])
            guard !Task.isCancelled else { return }
            if behind != incomingSHAs { incomingSHAs = behind }
            if ahead != outgoingSHAs { outgoingSHAs = ahead }
        }
    }

    public func syncState(of commit: CommitInfo) -> CommitSyncState? {
        if incomingSHAs.contains(commit.id) { return .incoming }
        return outgoingSHAs.contains(commit.id) ? .outgoing : nil
    }

    // MARK: - Filter

    public func setSearchText(_ text: String) {
        searchText = text
    }

    public var filteredCommits: [CommitInfo] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return commits }
        return commits.filter {
            $0.id.hasPrefix(query)
                || $0.message.lowercased().contains(query)
                || $0.authorName.lowercased().contains(query)
                || $0.authorEmail.lowercased().contains(query)
        }
    }

    public var isFiltering: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    // MARK: - Refs

    /// Looked up from the refs, since an upstream ahead of HEAD tops the log; a detached HEAD tops it.
    public var headSHA: String? {
        branches.first(where: \.isHEAD)?.targetSHA ?? (filterBranch == nil ? commits.first?.id : nil)
    }

    public var headBranchName: String? { branches.first(where: \.isHEAD)?.name }

    public func branches(at commit: CommitInfo) -> [BranchInfo] {
        branchesBySHA[commit.id] ?? []
    }

    public func tags(at commit: CommitInfo) -> [TagInfo] {
        tagsBySHA[commit.id] ?? []
    }

    /// HEAD first, then local, then remote branches; `origin/HEAD` aliases are dropped.
    private static func index(_ branches: [BranchInfo]) -> [String: [BranchInfo]] {
        Dictionary(grouping: branches.filter { !$0.id.hasSuffix("/HEAD") }, by: \.targetSHA)
            .mapValues { $0.sorted { ($0.isHEAD ? 0 : $0.isLocal ? 1 : 2) < ($1.isHEAD ? 0 : $1.isLocal ? 1 : 2) } }
    }

    public func commit(withID id: String) -> CommitInfo? {
        commits.first { $0.id == id }
    }

    // MARK: - Selection

    public func select(_ commit: CommitInfo) {
        var next = ListSelection<String>()
        next.select(commit.id)
        applySelection(next)
    }

    /// Takes a new selection and shows its focused commit in the detail pane.
    func applySelection(_ next: ListSelection<String>) {
        selection = next
        guard let id = next.focus, let commit = commit(withID: id) else { return clearSelection() }
        showDetail(for: commit)
    }

    private func showDetail(for commit: CommitInfo) {
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

    private func clearSelection() {
        detailTask?.cancel()
        selection.clear()
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
    func prefetchDiff(for commit: CommitInfo) {
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

    public func setLayout(_ layout: HistoryLayout) {
        self.layout = layout
        ViewModelPreferences.historyLayout = layout
    }

    public func selectDetailTab(_ tab: DetailTab) {
        detailTab = tab
        if tab == .tree, treeFiles.isEmpty { Task { await loadTree() } }
    }

    public func toggleFile(_ path: String) {
        if expandedPaths.contains(path) { expandedPaths.remove(path) } else { expandedPaths.insert(path) }
    }

    public func setAllFilesExpanded(_ expanded: Bool) {
        expandedPaths = expanded ? Set(commitDiffs.map(\.path)) : []
    }

    /// Shows a file from the tree in the changeset tab, expanded.
    public func revealInChangeset(_ path: String) {
        expandedPaths.insert(path)
        detailTab = .changeset
    }

    public func fileDiff(for path: String) -> FileDiff? {
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
        graphBuilder = CommitGraphBuilder()
        graphNodes = [:]
        appendGraph(commits)
    }

    /// A new page continues the open lanes; only a reload or a changed log rebuilds from the top.
    private func appendGraph(_ page: [CommitInfo]) {
        for node in graphBuilder.append(page) where graphNodes[node.id] == nil {
            graphNodes[node.id] = node
        }
        maxGraphColumns = graphBuilder.maxColumn + 1
    }
}

/// Everything the detail pane shows for one commit; each part fills in as it loads.
struct CommitDetails {
    var diffs: [FileDiff]?
    public var tree: [String]?
    var signature: SignatureStatus?

    func isComplete(needsTree: Bool) -> Bool {
        diffs != nil && signature != nil && (!needsTree || tree != nil)
    }
}
