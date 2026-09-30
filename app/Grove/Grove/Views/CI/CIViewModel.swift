// Views/CI/CIViewModel.swift
// Grove

import AppKit
import Foundation
import Observation

/// The Actions tab: workflow runs of the repository's hosting service, filtered by workflow, branch and status.
@MainActor
@Observable
final class CIViewModel {

    // MARK: - List State

    private(set) var runs: [CIRun] = []
    private(set) var workflows: [CIWorkflow] = []
    private(set) var query = CIRunQuery()
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var loadFailure: HostLoadFailure?
    /// The service the repository's remote points at, for labels like "Open on GitHub".
    private(set) var service: HostingServiceKind?
    private(set) var selectedRunID: Int?
    private(set) var actionError: String?

    /// Bumped by every list read, so an answer to an outdated filter is dropped.
    @ObservationIgnored private var loadGeneration = 0
    /// When the list first showed a queued or running run; nil while everything is finished.
    @ObservationIgnored private(set) var activeSince: Date?
    @ObservationIgnored private(set) var consecutiveFailures = 0
    /// The poll loop's current wait, cancelled to poll at once.
    @ObservationIgnored var pollWait: Task<Void, Error>?
    @ObservationIgnored var isWakingPoll = false

    let repository: any GitRepositoryProtocol
    let refs: RepositoryRefs
    /// Jobs of the selected run.
    let detail: CIRunDetailViewModel

    init(repository: any GitRepositoryProtocol, refs: RepositoryRefs? = nil) {
        self.repository = repository
        self.refs = refs ?? RepositoryRefs(repository: repository)
        detail = CIRunDetailViewModel(repository: repository)
    }

    // MARK: - Derived

    var selectedRun: CIRun? { runs.first { $0.id == selectedRunID } }

    /// "GitHub", …; generic until the remote has been read.
    var serviceName: String { service?.displayName ?? "the Host" }

    /// Local branches, plus the filtered one when it only exists on the remote.
    var branchCandidates: [String] {
        let names = refs.localBranches.map(\.name)
        let all = query.branch.map { names.contains($0) ? names : names + [$0] } ?? names
        return all.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: - Loading

    /// Reads workflows and runs; the list on screen stays until the new one lands.
    func refresh() async {
        service = await repository.hostingService()
        async let loadedWorkflows = try? repository.ciWorkflows()
        await loadRuns()
        if let loadedWorkflows = await loadedWorkflows, loadedWorkflows != workflows { workflows = loadedWorkflows }
    }

    /// `quietly` leaves the header spinner alone, for polls.
    private func loadRuns(quietly: Bool = false) async {
        loadGeneration += 1
        let generation = loadGeneration
        if !quietly { isLoading = true }
        defer { if generation == loadGeneration { isLoading = false; hasLoaded = true } }
        do {
            let loaded = try await repository.ciRuns(query)
            guard generation == loadGeneration else { return }
            await apply(loaded)
        } catch {
            guard generation == loadGeneration else { return }
            fail(error)
        }
    }

    private func apply(_ loaded: [CIRun]) async {
        if loaded != runs { runs = loaded }
        loadFailure = nil
        consecutiveFailures = 0
        if !runs.contains(where: \.status.isActive) {
            activeSince = nil
        } else if activeSince == nil {
            activeSince = Date()
        }
        if selectedRun == nil { selectedRunID = runs.first?.id }
        await detail.show(selectedRun)
    }

    private func fail(_ error: Error) {
        loadFailure = HostLoadFailure(error)
        consecutiveFailures += 1
    }

    // MARK: - Polling

    /// Runs the poll reads: the newest few, plus each run that was still going when last seen.
    static let pollPageSize = 10
    static let pollFollowUpLimit = 5

    /// One poll. With nothing active the whole list is read again; with active runs only what can have changed.
    func poll() async {
        guard hasLoaded, !isLoading else { return }
        guard runs.contains(where: \.status.isActive) else { return await loadRuns(quietly: true) }
        loadGeneration += 1
        let generation = loadGeneration
        do {
            let newest = try await repository.ciRuns(query.limited(to: Self.pollPageSize))
            let seen = Set(newest.map(\.id))
            var updated = newest
            var deleted: Set<Int> = []
            for run in runs.filter({ $0.status.isActive && !seen.contains($0.id) }).prefix(Self.pollFollowUpLimit) {
                do {
                    updated.append(try await repository.ciRun(id: run.id))
                } catch HostingError.http(status: 404, _) {
                    deleted.insert(run.id)
                }
            }
            guard generation == loadGeneration else { return }
            await apply(Self.merge(updated, into: runs.filter { !deleted.contains($0.id) }, query: query))
        } catch {
            guard generation == loadGeneration else { return }
            fail(error)
        }
    }

    /// `updates` replace the runs they describe and add new ones, newest first; a run that left the status filter is dropped.
    nonisolated static func merge(_ updates: [CIRun], into runs: [CIRun], query: CIRunQuery) -> [CIRun] {
        var byID = Dictionary(runs.map { ($0.id, $0) }) { $1 }
        for run in updates { byID[run.id] = run }
        return byID.values.filter { query.status == nil || $0.status == query.status }
            .sorted { ($0.createdDate, $0.id) > ($1.createdDate, $1.id) }
            .prefix(query.limit).map { $0 }
    }

    /// Seconds until the next poll should run.
    var pollInterval: TimeInterval {
        CIPollSchedule.interval(activeFor: activeSince.map { Date().timeIntervalSince($0) }, consecutiveFailures: consecutiveFailures)
    }

    // MARK: - Filters

    func setWorkflowFilter(_ id: Int?) async {
        await setQuery(CIRunQuery(workflowID: id, branch: query.branch, status: query.status))
    }

    func setBranchFilter(_ branch: String?) async {
        await setQuery(CIRunQuery(workflowID: query.workflowID, branch: branch, status: query.status))
    }

    func setStatusFilter(_ status: CIRunStatus?) async {
        await setQuery(CIRunQuery(workflowID: query.workflowID, branch: query.branch, status: status))
    }

    func clearFilters() async {
        await setQuery(CIRunQuery())
    }

    private func setQuery(_ new: CIRunQuery) async {
        guard new != query else { return }
        query = new
        await loadRuns()
    }

    // MARK: - Selection and actions

    func select(_ run: CIRun) async {
        selectedRunID = run.id
        await detail.show(run)
    }

    func openInBrowser(_ run: CIRun) {
        guard let url = URL(string: run.webURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func clearActionError() {
        actionError = nil
    }
}
