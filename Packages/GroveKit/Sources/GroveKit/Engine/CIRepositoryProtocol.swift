// Engine/CIRepositoryProtocol.swift
// GroveKit
//
// CI/CD runs of a repository, read from whichever service its remote points at.

import Foundation

@MainActor
public protocol CIRepositoryProtocol {
    /// Workflows defined in the repository, for the filter and for running one.
    func ciWorkflows() async throws -> [CIWorkflow]
    /// The newest runs matching `query`, newest first.
    func ciRuns(_ query: CIRunQuery) async throws -> [CIRun]
    func ciRun(id: Int) async throws -> CIRun
    /// How CI went for each branch's newest commit, keyed by branch name.
    func branchCIStatuses() async throws -> [String: BranchCIStatus]
    /// Jobs of the run's latest attempt, with their steps.
    func ciJobs(runID: Int) async throws -> [CIJob]
    /// Notes a finished job left, such as warnings and test failures.
    func ciAnnotations(jobID: Int) async throws -> [CIAnnotation]
    /// A finished job's log as plain text.
    func ciJobLog(jobID: Int) async throws -> String
    /// Files the run uploaded.
    func ciArtifacts(runID: Int) async throws -> [CIArtifact]
    /// Saves an artifact's zip at `destination`.
    func downloadCIArtifact(id: Int, to destination: URL) async throws
    /// Starts a new attempt of a finished run; `failedOnly` skips the jobs that passed.
    func rerunCIRun(id: Int, failedOnly: Bool) async throws
    func cancelCIRun(id: Int) async throws
    /// A workflow's definition file as it is on `ref`.
    func ciWorkflowFile(path: String, ref: String) async throws -> String
    /// Starts a workflow by hand on a branch or tag.
    func dispatchCIWorkflow(_ dispatch: CIDispatch) async throws
}

// Repositories without CI support behave like ones without a hosted remote.
extension CIRepositoryProtocol {
    public func ciWorkflows() async throws -> [CIWorkflow] { throw HostingError.noHostedRemote }
    public func ciRuns(_ query: CIRunQuery) async throws -> [CIRun] { throw HostingError.noHostedRemote }
    public func ciRun(id: Int) async throws -> CIRun { throw HostingError.noHostedRemote }
    public func branchCIStatuses() async throws -> [String: BranchCIStatus] { throw HostingError.noHostedRemote }
    public func ciJobs(runID: Int) async throws -> [CIJob] { throw HostingError.noHostedRemote }
    public func ciAnnotations(jobID: Int) async throws -> [CIAnnotation] { throw HostingError.noHostedRemote }
    public func ciJobLog(jobID: Int) async throws -> String { throw HostingError.noHostedRemote }
    public func ciArtifacts(runID: Int) async throws -> [CIArtifact] { throw HostingError.noHostedRemote }
    public func downloadCIArtifact(id: Int, to destination: URL) async throws { throw HostingError.noHostedRemote }
    public func rerunCIRun(id: Int, failedOnly: Bool) async throws { throw HostingError.noHostedRemote }
    public func cancelCIRun(id: Int) async throws { throw HostingError.noHostedRemote }
    public func ciWorkflowFile(path: String, ref: String) async throws -> String { throw HostingError.noHostedRemote }
    public func dispatchCIWorkflow(_ dispatch: CIDispatch) async throws { throw HostingError.noHostedRemote }
}
