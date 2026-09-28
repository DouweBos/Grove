// Views/WorkingCopy/WorkingDiffCache.swift
// Grove

import Foundation

/// Working-copy diffs per file, side and whitespace mode, so switching between files is instant.
/// Working-tree content is mutable: entries from before the last status refresh are shown but re-read.
struct WorkingDiffCache {

    struct Key: Hashable {
        let path: String
        let side: DiffSide
        let ignoreWhitespace: Bool
    }

    struct Hit {
        let diff: DiffResult
        /// False when a refresh has run since, so the caller should re-read the diff.
        let isCurrent: Bool
    }

    private struct Entry {
        let diff: DiffResult
        let status: StatusEntry
        let generation: Int
    }

    private var entries = LRUCache<Key, Entry>(capacity: 50)
    /// Bumped per status refresh; read it before starting a diff so a slow load isn't stamped as current.
    private(set) var generation = 0

    var isEmpty: Bool { entries.isEmpty }

    /// Call after every status refresh; drops files whose status changed or that are no longer listed.
    mutating func statusRefreshed(_ status: [StatusEntry]) {
        generation += 1
        let byPath = Dictionary(status.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        let stale = entries.keys.filter { entries.peek($0)?.status != byPath[$0.path] }
        for key in stale { entries.removeValue(for: key) }
    }

    mutating func lookup(_ key: Key) -> Hit? {
        entries.value(for: key).map { Hit(diff: $0.diff, isCurrent: $0.generation == generation) }
    }

    mutating func store(_ diff: DiffResult, for key: Key, status: StatusEntry, loadedAt loadGeneration: Int) {
        entries.insert(Entry(diff: diff, status: status, generation: loadGeneration), for: key)
    }
}
