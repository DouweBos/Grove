// Views/CI/CIRunDetailViewModel.swift
// Grove

import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

enum CIRunDetailTab: String, CaseIterable, Hashable {
    case jobs = "Jobs"
    case artifacts = "Artifacts"
}

/// The selected run's jobs, steps and artifacts.
@MainActor
@Observable
final class CIRunDetailViewModel {

    /// Where an artifact's download stands.
    enum Download: Equatable {
        case running
        case saved(URL)
        case failed(String)
    }

    private(set) var run: CIRun?
    private(set) var activeTab: CIRunDetailTab = .jobs
    private(set) var jobs: [CIJob] = []
    // Loads are tracked by the run they're for: a flag would stay set when the selection moves on mid-load.
    private var loadingJobsRunID: Int?
    private var loadingArtifactsRunID: Int?
    private(set) var jobsError: String?
    private(set) var selectedJobID: Int?
    private(set) var artifacts: [CIArtifact] = []
    private(set) var artifactsError: String?
    private(set) var downloads: [Int: Download] = [:]

    // Keyed by attempt and update date too, so a re-run or a finished run misses instead of showing its old jobs.
    @ObservationIgnored private var cache = LRUCache<CIRunDetailKey, CIRunDetails>(capacity: 30)

    let repository: any GitRepositoryProtocol
    /// The selected job's log.
    let log: CILogViewModel
    /// Asks where to save an artifact; nil when cancelled. Replaced in tests.
    @ObservationIgnored var chooseDestination: (CIArtifact) async -> URL? = { artifact in
        await SavePanel.choose(name: "\(artifact.name).zip", message: "Save the artifact's zip archive.", type: .zip)
    }

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
        log = CILogViewModel(repository: repository)
    }

    var selectedJob: CIJob? { jobs.first { $0.id == selectedJobID } }

    /// The shown run's jobs are being read for the first time.
    var isLoadingJobs: Bool { run != nil && loadingJobsRunID == run?.id }
    var isLoadingArtifacts: Bool { run != nil && loadingArtifactsRunID == run?.id }

    // MARK: - Loading

    /// Shows `run`: from the cache when it's finished and unchanged, else read from the host.
    /// The same run in a newer state keeps its content on screen while it's re-read.
    func show(_ run: CIRun?) async {
        guard let run else { return clear() }
        let previous = self.run
        let key = CIRunDetailKey(run)
        if let previous, CIRunDetailKey(previous) == key, !run.status.isActive, cache.peek(key)?.jobs != nil { return }
        self.run = run
        jobsError = nil
        artifactsError = nil
        let cached = cache.value(for: key)
        if previous?.id != run.id {
            artifacts = cached?.artifacts ?? []
            if cached?.jobs == nil {
                jobs = []
                selectedJobID = nil
                await log.show(nil)
            }
        }
        if let cachedJobs = cached?.jobs { await apply(cachedJobs) }
        async let jobsRead: Void = (cached?.jobs == nil || run.status.isActive) ? loadJobs(for: run) : ()
        async let artifactsRead: Void = needsArtifacts(run, cached: cached) ? loadArtifacts(for: run) : ()
        _ = await (jobsRead, artifactsRead)
    }

    /// A finished run's artifacts are read once; a running one's only while their tab is open, since they're still arriving.
    private func needsArtifacts(_ run: CIRun, cached: CIRunDetails?) -> Bool {
        run.status.isActive ? activeTab == .artifacts : cached?.artifacts == nil
    }

    /// Reads the shown run again, e.g. after a failed read.
    func reload() async {
        guard let run else { return }
        async let jobsRead: Void = loadJobs(for: run)
        async let artifactsRead: Void = loadArtifacts(for: run)
        _ = await (jobsRead, artifactsRead)
    }

    func selectTab(_ tab: CIRunDetailTab) async {
        activeTab = tab
        if tab == .artifacts, let run, run.status.isActive { await loadArtifacts(for: run) }
    }

    private func clear() {
        run = nil
        jobs = []
        artifacts = []
        selectedJobID = nil
        jobsError = nil
        artifactsError = nil
        Task { await log.show(nil) }
    }

    private func loadJobs(for run: CIRun) async {
        let key = CIRunDetailKey(run)
        if jobs.isEmpty { loadingJobsRunID = run.id }
        let result: Result<[CIJob], Error>
        do {
            result = .success(try await repository.ciJobs(runID: run.id))
        } catch {
            result = .failure(error)
        }
        // Cleared before the jobs are applied: applying also reads the selected job's log, which the jobs shouldn't wait for.
        if loadingJobsRunID == run.id { loadingJobsRunID = nil }
        switch result {
        case .success(let loaded):
            cache.update(key, default: CIRunDetails()) { $0.jobs = loaded }
            guard self.run.map(CIRunDetailKey.init) == key else { return }
            jobsError = nil
            await apply(loaded)
        case .failure(let error):
            guard self.run?.id == run.id else { return }
            jobsError = error.localizedDescription
        }
    }

    private func loadArtifacts(for run: CIRun) async {
        let key = CIRunDetailKey(run)
        if artifacts.isEmpty { loadingArtifactsRunID = run.id }
        defer { if loadingArtifactsRunID == run.id { loadingArtifactsRunID = nil } }
        do {
            let loaded = try await repository.ciArtifacts(runID: run.id)
            cache.update(key, default: CIRunDetails()) { $0.artifacts = loaded }
            guard self.run.map(CIRunDetailKey.init) == key else { return }
            artifactsError = nil
            if loaded != artifacts { artifacts = loaded }
        } catch {
            guard self.run?.id == run.id else { return }
            artifactsError = error.localizedDescription
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

    // MARK: - Artifacts

    /// Asks where to save the artifact's zip, then downloads it there.
    func downloadArtifact(_ artifact: CIArtifact) async {
        guard !artifact.isExpired, downloads[artifact.id] != .running, let destination = await chooseDestination(artifact) else { return }
        downloads[artifact.id] = .running
        do {
            try await repository.downloadCIArtifact(id: artifact.id, to: destination)
            downloads[artifact.id] = .saved(destination)
        } catch {
            downloads[artifact.id] = .failed(error.localizedDescription)
        }
    }

    func revealDownload(of artifact: CIArtifact) {
        guard case .saved(let url) = downloads[artifact.id] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
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

/// Detail content of one run; each part fills in when first read.
struct CIRunDetails {
    var jobs: [CIJob]?
    var artifacts: [CIArtifact]?
}
