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
        return ci.runs.filter { run in
            (query.workflowID == nil || run.workflowID == query.workflowID) && (query.branch == nil || run.branch == query.branch)
                && (query.status == nil || run.status == query.status)
        }
    }
}
