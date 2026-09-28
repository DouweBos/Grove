// Mocks/MockGitRepository+WorkingCopy.swift
// Grove
//
// Working-copy file actions, patches and snapshots for previews; they only record the call.

import Foundation

extension MockGitRepository {

    func ignore(patterns: [String], localOnly: Bool) async throws {
        await simulateLatency()
    }

    func stopTracking(paths: [String]) async throws {
        await simulateLatency()
    }

    func moveFile(from source: String, to destination: String) async throws {
        await simulateLatency()
    }
}
