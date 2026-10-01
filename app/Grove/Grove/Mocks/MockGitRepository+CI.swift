// Mocks/MockGitRepository+CI.swift
// Grove

import Foundation

/// What the mock's CI answers with, and what it was asked; tests set and read it through `MockGitRepository.ci`.
struct MockCIState {
    var workflows = MockData.ciWorkflows
    var runs = MockData.ciRuns
    /// Thrown by every CI call while set.
    var error: HostingError?
    var queries: [CIRunQuery] = []
    /// Jobs per run id; runs without an entry get `MockData.ciJobs(for:)`.
    var jobs: [Int: [CIJob]] = [:]
    var jobRequests: [Int] = []
    var runRequests: [Int] = []
    /// Log text per job id; jobs without an entry get `MockData.ciLog(for:)`.
    var logs: [Int: String] = [:]
    var logRequests: [Int] = []
    /// Annotations per job id; jobs without an entry get `MockData.ciAnnotations(for:)`.
    var annotations: [Int: [CIAnnotation]] = [:]
    var annotationRequests: [Int] = []
    var artifactRequests: [Int] = []
    /// Artifact ids and where each was saved.
    var downloads: [(id: Int, destination: URL)] = []
    /// Writes in order, e.g. `"rerun 145"`, `"rerun-failed 145"`, `"cancel 148"`.
    var operations: [String] = []
    var workflowFiles = MockData.ciWorkflowFiles
    var workflowFileRequests: [String] = []
    var dispatches: [CIDispatch] = []
    var branchStatusRequests = 0
    /// Run and job ids whose jobs or log read doesn't answer until they're removed, to test slow reads.
    var held: Set<Int> = []
}

extension MockGitRepository {

    func ciWorkflows() async throws -> [CIWorkflow] {
        await simulateLatency(20_000_000)
        if let error = ci.error { throw error }
        return ci.workflows
    }

    func ciRuns(_ query: CIRunQuery) async throws -> [CIRun] {
        ci.queries.append(query)
        await simulateLatency(20_000_000)
        if let error = ci.error { throw error }
        return Array(ci.runs.filter { run in
            (query.workflowID == nil || run.workflowID == query.workflowID) && (query.branch == nil || run.branch == query.branch)
                && (query.status == nil || run.status == query.status)
        }.dropFirst((query.page - 1) * query.limit).prefix(query.limit))
    }

    func ciAnnotations(jobID: Int) async throws -> [CIAnnotation] {
        ci.annotationRequests.append(jobID)
        await simulateLatency(20_000_000)
        if let error = ci.error { throw error }
        if let annotations = ci.annotations[jobID] { return annotations }
        let jobs = ci.jobs.values.joined() + ci.runs.flatMap(MockData.ciJobs(for:))
        return jobs.first { $0.id == jobID }.map(MockData.ciAnnotations(for:)) ?? []
    }

    func ciJobLog(jobID: Int) async throws -> String {
        ci.logRequests.append(jobID)
        await simulateLatency(20_000_000)
        await waitWhileHeld(jobID)
        if let error = ci.error { throw error }
        if let log = ci.logs[jobID] { return log }
        let jobs = ci.jobs.values.joined() + ci.runs.flatMap(MockData.ciJobs(for:))
        return jobs.first { $0.id == jobID }.map(MockData.ciLog(for:)) ?? ""
    }

    func ciArtifacts(runID: Int) async throws -> [CIArtifact] {
        ci.artifactRequests.append(runID)
        await simulateLatency(20_000_000)
        if let error = ci.error { throw error }
        return ci.runs.first { $0.id == runID }.map(MockData.ciArtifacts(for:)) ?? []
    }

    func downloadCIArtifact(id: Int, to destination: URL) async throws {
        await simulateLatency(20_000_000)
        if let error = ci.error { throw error }
        ci.downloads.append((id, destination))
    }

    /// Like the host: the run goes back to queued as its next attempt.
    func rerunCIRun(id: Int, failedOnly: Bool) async throws {
        await simulateLatency(20_000_000)
        if let error = ci.error { throw error }
        ci.operations.append("\(failedOnly ? "rerun-failed" : "rerun") \(id)")
        replaceRun(id) { $0.with(status: .queued, attempt: $0.attempt + 1) }
    }

    func cancelCIRun(id: Int) async throws {
        await simulateLatency(20_000_000)
        if let error = ci.error { throw error }
        ci.operations.append("cancel \(id)")
        replaceRun(id) { $0.with(status: .cancelled, attempt: $0.attempt) }
    }

    private func waitWhileHeld(_ id: Int) async {
        while ci.held.contains(id) { try? await Task.sleep(nanoseconds: 5_000_000) }
    }

    private func replaceRun(_ id: Int, _ change: (CIRun) -> CIRun) {
        guard let index = ci.runs.firstIndex(where: { $0.id == id }) else { return }
        ci.runs[index] = change(ci.runs[index])
    }

    func ciWorkflowFile(path: String, ref: String) async throws -> String {
        ci.workflowFileRequests.append("\(path)@\(ref)")
        await simulateLatency(20_000_000)
        if let error = ci.error { throw error }
        guard let file = ci.workflowFiles[path] else { throw HostingError.http(status: 404, message: "Not Found") }
        return file
    }

    /// Like the host: answers at once, and the run shows up in the list afterwards.
    func dispatchCIWorkflow(_ dispatch: CIDispatch) async throws {
        await simulateLatency(20_000_000)
        if let error = ci.error { throw error }
        ci.dispatches.append(dispatch)
        let id = (ci.runs.map(\.id).max() ?? 0) + 1
        let name = ci.workflows.first { $0.id == dispatch.workflowID }?.name ?? ""
        ci.runs.insert(CIRun(id: id, number: id - 100, attempt: 1, title: name, workflowID: dispatch.workflowID, workflowName: name,
                             event: "workflow_dispatch", branch: dispatch.ref, headSHA: MockData.commits[0].id, status: .queued,
                             actor: MockData.authorJane.name, createdDate: Date(), updatedDate: Date(), startedDate: nil,
                             webURL: "https://github.com/example/app/actions/runs/\(id)"), at: 0)
    }

    func branchCIStatuses() async throws -> [String: BranchCIStatus] {
        ci.branchStatusRequests += 1
        if let error = ci.error { throw error }
        return BranchCIStatus.index(ci.runs)
    }

    func ciRun(id: Int) async throws -> CIRun {
        ci.runRequests.append(id)
        if let error = ci.error { throw error }
        guard let run = ci.runs.first(where: { $0.id == id }) else { throw HostingError.http(status: 404, message: "Not Found") }
        return run
    }

    func ciJobs(runID: Int) async throws -> [CIJob] {
        ci.jobRequests.append(runID)
        await simulateLatency(20_000_000)
        await waitWhileHeld(runID)
        if let error = ci.error { throw error }
        if let jobs = ci.jobs[runID] { return jobs }
        return ci.runs.first { $0.id == runID }.map(MockData.ciJobs(for:)) ?? []
    }
}
