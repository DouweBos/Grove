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
    var artifactRequests: [Int] = []
    /// Artifact ids and where each was saved.
    var downloads: [(id: Int, destination: URL)] = []
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
        }.prefix(query.limit))
    }

    func ciJobLog(jobID: Int) async throws -> String {
        ci.logRequests.append(jobID)
        await simulateLatency(20_000_000)
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

    func ciRun(id: Int) async throws -> CIRun {
        ci.runRequests.append(id)
        if let error = ci.error { throw error }
        guard let run = ci.runs.first(where: { $0.id == id }) else { throw HostingError.http(status: 404, message: "Not Found") }
        return run
    }

    func ciJobs(runID: Int) async throws -> [CIJob] {
        ci.jobRequests.append(runID)
        await simulateLatency(20_000_000)
        if let error = ci.error { throw error }
        if let jobs = ci.jobs[runID] { return jobs }
        return ci.runs.first { $0.id == runID }.map(MockData.ciJobs(for:)) ?? []
    }
}
