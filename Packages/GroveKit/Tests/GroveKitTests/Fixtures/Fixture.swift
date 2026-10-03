// Fixture.swift
// GroveKitTests
//
// Test-facing entry point: `Fixture.make(.small, states: [.mergeConflict])` builds a scratch repository in a temp dir.

import Foundation

struct Fixture {
    let spec: FixtureSpec
    let result: FixtureResult

    var root: URL { result.root }
    var repo: URL { result.repo }
    var origin: URL { result.origin }

    /// A fresh fixture in its own temp directory; call `remove()` when done.
    static func make(_ preset: FixturePreset = .small, states: [FixtureState] = [], seed: UInt64 = 1,
                     customize: (inout FixtureSpec) -> Void = { _ in }) throws -> Fixture {
        var spec = FixtureSpec(preset, seed: seed, states: states)
        customize(&spec)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-fixture-\(UUID().uuidString)")
        return Fixture(spec: spec, result: try FixtureGenerator(spec: spec, root: root).generate())
    }

    /// Shared, read-only fixture keyed by spec and generator version; reused across test runs.
    static func cached(_ spec: FixtureSpec) throws -> Fixture {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        let root = cacheDirectory.appendingPathComponent(spec.cacheKey)
        let manager = FileManager.default
        if manager.fileExists(atPath: root.appendingPathComponent(FixtureGenerator.markerName).path) {
            return Fixture(spec: spec, result: try FixtureGenerator.describe(root: root, seconds: 0))
        }
        // A folder without the marker is a generation that crashed halfway.
        if manager.fileExists(atPath: root.path) { try manager.removeItem(at: root) }
        return Fixture(spec: spec, result: try FixtureGenerator(spec: spec, root: root).generate())
    }

    static var cacheDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("grove-fixtures")
    }

    private static let cacheLock = NSLock()

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// Runs git in the fixture repository (or `directory`) with the generator's isolated config.
    @discardableResult
    func git(_ arguments: [String], in directory: URL? = nil) throws -> String {
        try FixtureGit.run(arguments, in: directory ?? repo)
    }
}
