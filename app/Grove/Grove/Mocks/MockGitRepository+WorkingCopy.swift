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

    func restoreFile(_ path: String, from revision: String, revisionPath: String) async throws {
        await simulateLatency()
    }

    func patch(paths: [String], staged: Bool) async throws -> String {
        await simulateLatency()
        return paths.map { "diff --git a/\($0) b/\($0)\n" }.joined()
    }

    func applyPatch(at file: URL, toIndex: Bool, checkOnly: Bool) async throws {
        await simulateLatency()
    }

    @discardableResult
    func saveSnapshot(message: String, includeUntracked: Bool) async throws -> Bool {
        await simulateLatency()
        return true
    }
}
