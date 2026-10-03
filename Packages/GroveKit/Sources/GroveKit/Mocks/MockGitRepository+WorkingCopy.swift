// Mocks/MockGitRepository+WorkingCopy.swift
// GroveKit
//
// Working-copy file actions, patches and snapshots for previews; they only record the call.

import Foundation

extension MockGitRepository {

    public func ignore(patterns: [String], localOnly: Bool) async throws {
        await simulateLatency()
    }

    public func stopTracking(paths: [String]) async throws {
        await simulateLatency()
    }

    public func moveFile(from source: String, to destination: String) async throws {
        await simulateLatency()
    }

    public func restoreFile(_ path: String, from revision: String, revisionPath: String) async throws {
        await simulateLatency()
    }

    public func patch(paths: [String], staged: Bool) async throws -> String {
        await simulateLatency()
        return paths.map { "diff --git a/\($0) b/\($0)\n" }.joined()
    }

    public func applyPatch(at file: URL, toIndex: Bool, checkOnly: Bool) async throws {
        await simulateLatency()
    }

    public func commitTemplate() async -> String? {
        nil
    }

    @discardableResult
    public func saveSnapshot(message: String, includeUntracked: Bool) async throws -> Bool {
        await simulateLatency()
        return true
    }
}
