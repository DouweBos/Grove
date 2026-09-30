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

    private func loadRuns() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false; hasLoaded = true } }
        do {
            let loaded = try await repository.ciRuns(query)
            guard generation == loadGeneration else { return }
            if loaded != runs { runs = loaded }
            loadFailure = nil
            if selectedRun == nil { selectedRunID = runs.first?.id }
            await detail.show(selectedRun)
        } catch {
            guard generation == loadGeneration else { return }
            loadFailure = HostLoadFailure(error)
        }
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
