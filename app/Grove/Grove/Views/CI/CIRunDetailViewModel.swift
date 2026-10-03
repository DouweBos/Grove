// Views/CI/CIRunDetailViewModel.swift
// Grove

import AppKit
import Foundation
import GroveKit
import Observation
import UniformTypeIdentifiers

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
    private(set) var jobs: [CIJob] = []
    // Loads are tracked by the run they're for: a flag would stay set when the selection moves on mid-load.
    private var loadingJobsRunID: Int?
    private var loadingArtifactsRunID: Int?
    private(set) var jobsError: String?
    /// The job whose steps and log are shown; nil shows the run's summary.
    private(set) var selectedJobID: Int?
    private(set) var artifacts: [CIArtifact] = []
    private(set) var artifactsError: String?
    private(set) var downloads: [Int: Download] = [:]
    /// The workflow's jobs and their `needs`, read from the file at the run's commit.
    private var graphDefinitions: (source: String, jobs: [WorkflowJobDefinition])?
    private var loadingGraphSource: String?
    private(set) var graphError: String?
    private(set) var graphZoom: CGFloat = 1
    /// How far the graph is dragged from its top-left; the view clamps it to what the graph's size allows.
    private(set) var graphPan: CGSize = .zero
    /// Per finished job, which leaves them as they are; a job missing hasn't been read yet.
    private(set) var annotationsByJob: [Int: [CIAnnotation]] = [:]
    @ObservationIgnored private var loadingAnnotationJobs: Set<Int> = []
    @ObservationIgnored private var definitionCache: [String: [WorkflowJobDefinition]] = [:]

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

    /// The run's jobs as the workflow wires them; each job in a column of its own until the file has been read.
    var graph: CIGraph {
        let definitions = graphDefinitions.flatMap { $0.source == graphSource ? $0.jobs : nil } ?? []
        return CIGraph.build(definitions: definitions, jobs: jobs)
    }

    /// The shown jobs' annotations, failures first, then in job order.
    var annotations: [(job: CIJob, annotation: CIAnnotation)] {
        jobs.flatMap { job in (annotationsByJob[job.id] ?? []).map { (job, $0) } }
            .enumerated().sorted { ($0.element.annotation.level, $0.offset) < ($1.element.annotation.level, $1.offset) }
            .map(\.element)
    }

    var isLoadingGraph: Bool { loadingGraphSource != nil && loadingGraphSource == graphSource }

    /// The workflow file at the commit the run ran on, since the file may have changed since.
    private var graphSource: String? {
        guard let run, !run.workflowPath.isEmpty else { return nil }
        return "\(run.workflowPath)@\(run.headSHA)"
    }

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
            graphPan = .zero
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
        async let graphRead: Void = loadGraph()
        _ = await (jobsRead, artifactsRead, graphRead)
    }

    /// A finished run's artifacts are read once; a running one's on each refresh while the summary shows, since they're still arriving.
    private func needsArtifacts(_ run: CIRun, cached: CIRunDetails?) -> Bool {
        run.status.isActive ? selectedJobID == nil : cached?.artifacts == nil
    }

    /// Reads the shown run again, e.g. after a failed read.
    func reload() async {
        guard let run else { return }
        async let jobsRead: Void = loadJobs(for: run)
        async let artifactsRead: Void = loadArtifacts(for: run)
        _ = await (jobsRead, artifactsRead)
    }

    /// Reads the workflow's job definitions once per file and commit.
    private func loadGraph() async {
        guard let source = graphSource, let run, graphDefinitions?.source != source else { return }
        if let cached = definitionCache[source] { return graphDefinitions = (source, cached) }
        guard loadingGraphSource != source else { return }
        loadingGraphSource = source
        defer { if loadingGraphSource == source { loadingGraphSource = nil } }
        do {
            let definitions = WorkflowJobsParser.parse(try await repository.ciWorkflowFile(path: run.workflowPath, ref: run.headSHA))
            definitionCache[source] = definitions
            guard graphSource == source else { return }
            graphDefinitions = (source, definitions)
            graphError = nil
        } catch {
            guard graphSource == source else { return }
            graphError = error.localizedDescription
        }
    }

    /// From the graph: shows the node's job's steps and log.
    func open(_ node: CIGraph.Node) async {
        guard let job = node.jobs.first(where: { $0.status == .failure }) ?? node.jobs.first else { return }
        await selectJob(job)
    }

    static let graphZoomRange: ClosedRange<CGFloat> = 0.5...1.5

    func zoomGraph(by step: CGFloat) {
        graphZoom = min(max(graphZoom + step, Self.graphZoomRange.lowerBound), Self.graphZoomRange.upperBound)
    }

    func resetGraphZoom() {
        graphZoom = 1
        graphPan = .zero
    }

    func panGraph(to offset: CGSize) {
        graphPan = offset
    }

    /// A job's log is shown, which going back leaves for the summary.
    var canReturnToSummary: Bool { selectedJobID != nil }

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

    /// Keeps the selected job when it's still there; otherwise back to the graph.
    private func apply(_ loaded: [CIJob]) async {
        if loaded != jobs { jobs = loaded }
        if selectedJob == nil { selectedJobID = nil }
        async let logRead: Void = log.show(selectedJob)
        async let annotationsRead: Void = loadAnnotations(for: loaded)
        _ = await (logRead, annotationsRead)
    }

    /// Reads each finished job's annotations once; a failed read is left for the next refresh, since they're only extra detail.
    private func loadAnnotations(for jobs: [CIJob]) async {
        let pending = jobs.filter { !$0.status.isActive && $0.status != .skipped && annotationsByJob[$0.id] == nil }
            .map(\.id).filter { !loadingAnnotationJobs.contains($0) }
        guard !pending.isEmpty else { return }
        loadingAnnotationJobs.formUnion(pending)
        defer { loadingAnnotationJobs.subtract(pending) }
        await withTaskGroup(of: (Int, [CIAnnotation]?).self) { group in
            for id in pending {
                group.addTask { @MainActor in (id, try? await self.repository.ciAnnotations(jobID: id)) }
            }
            for await (id, loaded) in group {
                if let loaded { annotationsByJob[id] = loaded }
            }
        }
    }

    // MARK: - Selection

    func selectJob(_ job: CIJob) async {
        selectedJobID = job.id
        await log.show(job)
    }

    func showSummary() async {
        selectedJobID = nil
        await log.show(nil)
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
