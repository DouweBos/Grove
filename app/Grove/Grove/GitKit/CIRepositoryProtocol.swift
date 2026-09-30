// GitKit/CIRepositoryProtocol.swift
// Grove
//
// CI/CD runs of a repository, read from whichever service its remote points at.

import Foundation

@MainActor
protocol CIRepositoryProtocol {
    /// Workflows defined in the repository, for the filter and for running one.
    func ciWorkflows() async throws -> [CIWorkflow]
    /// The newest runs matching `query`, newest first.
    func ciRuns(_ query: CIRunQuery) async throws -> [CIRun]
    func ciRun(id: Int) async throws -> CIRun
    /// Jobs of the run's latest attempt, with their steps.
    func ciJobs(runID: Int) async throws -> [CIJob]
}

// Repositories without CI support behave like ones without a hosted remote.
extension CIRepositoryProtocol {
    func ciWorkflows() async throws -> [CIWorkflow] { throw HostingError.noHostedRemote }
    func ciRuns(_ query: CIRunQuery) async throws -> [CIRun] { throw HostingError.noHostedRemote }
    func ciRun(id: Int) async throws -> CIRun { throw HostingError.noHostedRemote }
    func ciJobs(runID: Int) async throws -> [CIJob] { throw HostingError.noHostedRemote }
}
