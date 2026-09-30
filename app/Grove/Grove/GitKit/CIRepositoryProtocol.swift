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
}

// Repositories without CI support behave like ones without a hosted remote.
extension CIRepositoryProtocol {
    func ciWorkflows() async throws -> [CIWorkflow] { throw HostingError.noHostedRemote }
    func ciRuns(_ query: CIRunQuery) async throws -> [CIRun] { throw HostingError.noHostedRemote }
}
