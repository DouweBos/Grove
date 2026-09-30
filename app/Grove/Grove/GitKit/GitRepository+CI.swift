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

    func ciJobs(runID: Int) async throws -> [CIJob] {
        try await ciHost().jobs(runID: runID)
    }
}
