// Views/CI/CIRunDetailViewModel.swift
// Grove

import Foundation
import Observation

/// The selected run's jobs and steps.
@MainActor
@Observable
final class CIRunDetailViewModel {

    private(set) var run: CIRun?
    private(set) var jobs: [CIJob] = []
    private(set) var isLoadingJobs = false
    private(set) var jobsError: String?
    private(set) var selectedJobID: Int?

    // Keyed by attempt and update date too, so a re-run or a finished run misses instead of showing its old jobs.
    @ObservationIgnored private var cache = LRUCache<CIRunDetailKey, CIRunDetails>(capacity: 30)

    let repository: any GitRepositoryProtocol
    /// The selected job's log.
    let log: CILogViewModel

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
        log = CILogViewModel(repository: repository)
    }

    var selectedJob: CIJob? { jobs.first { $0.id == selectedJobID } }

    // MARK: - Loading

    /// Shows `run`: from the cache when it's finished and unchanged, else read from the host.
    /// The same run in a newer state keeps its jobs on screen while they're re-read.
    func show(_ run: CIRun?) async {
        guard let run else { return clear() }
        let previous = self.run
        let key = CIRunDetailKey(run)
        if let previous, CIRunDetailKey(previous) == key, !run.status.isActive, cache.peek(key)?.jobs != nil { return }
        self.run = run
        jobsError = nil
        if let cached = cache.value(for: key)?.jobs {
            await apply(cached)
            if !run.status.isActive { return }
        } else if previous?.id != run.id {
            jobs = []
            selectedJobID = nil
            await log.show(nil)
        }
        await loadJobs(for: run)
    }

    /// Reads the shown run's jobs again, e.g. from the reload button.
    func reload() async {
        guard let run else { return }
        await loadJobs(for: run)
    }

    private func clear() {
        run = nil
        jobs = []
        selectedJobID = nil
        isLoadingJobs = false
        jobsError = nil
        Task { await log.show(nil) }
    }

    private func loadJobs(for run: CIRun) async {
        let key = CIRunDetailKey(run)
        if jobs.isEmpty { isLoadingJobs = true }
        defer { if self.run?.id == run.id { isLoadingJobs = false } }
        do {
            let loaded = try await repository.ciJobs(runID: run.id)
            cache.update(key, default: CIRunDetails()) { $0.jobs = loaded }
            guard self.run.map(CIRunDetailKey.init) == key else { return }
            jobsError = nil
            await apply(loaded)
        } catch {
            guard self.run?.id == run.id else { return }
            jobsError = error.localizedDescription
        }
    }

    /// Keeps the selected job when it's still there; otherwise the first failed job, else the first.
    private func apply(_ loaded: [CIJob]) async {
        if loaded != jobs { jobs = loaded }
        if selectedJob == nil {
            selectedJobID = (loaded.first { $0.status == .failure } ?? loaded.first)?.id
        }
        await log.show(selectedJob)
    }

    // MARK: - Selection

    func selectJob(_ job: CIJob) async {
        selectedJobID = job.id
        await log.show(job)
    }
}

/// Identity of a run's detail content; the update date moves whenever the host sees a change.
struct CIRunDetailKey: Hashable {
    let id: Int
    let attempt: Int
    let updated: Date

    init(_ run: CIRun) {
        id = run.id
        attempt = run.attempt
        updated = run.updatedDate
    }
}

/// Detail content of one run; each part fills in when first shown.
struct CIRunDetails {
    var jobs: [CIJob]?
}
