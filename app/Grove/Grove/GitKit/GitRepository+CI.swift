// GitKit/GitRepository+CI.swift
// Grove
//
// CI runs through whichever service the repository's remote points at.

import Foundation
import os

extension GitRepository {

    /// Read each time so a remote added or changed in Settings takes effect at once.
    private func ciHost() async throws -> any CIHost {
        try CIHostResolver.resolve(remotes: try await remotes())
    }

    func ciWorkflows() async throws -> [CIWorkflow] {
        try await ciHost().workflows()
    }

    func ciRuns(_ query: CIRunQuery) async throws -> [CIRun] {
        try await ciHost().runs(query)
    }

    func ciRun(id: Int) async throws -> CIRun {
        try await ciHost().run(id: id)
    }

    func branchCIStatuses() async throws -> [String: BranchCIStatus] {
        try await ciHost().branchStatuses()
    }

    func ciJobs(runID: Int) async throws -> [CIJob] {
        try await ciHost().jobs(runID: runID)
    }

    func ciJobLog(jobID: Int) async throws -> String {
        try await ciHost().log(jobID: jobID)
    }

    func ciArtifacts(runID: Int) async throws -> [CIArtifact] {
        try await ciHost().artifacts(runID: runID)
    }

    func downloadCIArtifact(id: Int, to destination: URL) async throws {
        Logger.gitRepository.info("Downloading artifact \(id, privacy: .public) in \(self.displayName, privacy: .public)")
        try await ciHost().downloadArtifact(id: id, to: destination)
    }

    func rerunCIRun(id: Int, failedOnly: Bool) async throws {
        Logger.gitRepository.info("Re-running run \(id, privacy: .public) in \(self.displayName, privacy: .public)")
        try await ciHost().rerun(runID: id, failedOnly: failedOnly)
    }

    func ciWorkflowFile(path: String, ref: String) async throws -> String {
        try await ciHost().workflowFile(path: path, ref: ref)
    }

    func dispatchCIWorkflow(_ dispatch: CIDispatch) async throws {
        Logger.gitRepository.info("Running workflow \(dispatch.workflowID, privacy: .public) on \(dispatch.ref, privacy: .public)")
        try await ciHost().dispatch(dispatch)
    }

    func cancelCIRun(id: Int) async throws {
        Logger.gitRepository.info("Cancelling run \(id, privacy: .public) in \(self.displayName, privacy: .public)")
        try await ciHost().cancel(runID: id)
    }
}
