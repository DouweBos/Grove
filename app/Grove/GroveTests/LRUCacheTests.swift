// LRUCacheTests.swift
// GroveTests

import Foundation
import Testing
@testable import Grove

struct LRUCacheTests {

    @Test func evictsLeastRecentlyUsed() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        _ = cache.value(for: "a")
        cache.insert(3, for: "c")
        #expect(cache.peek("a") == 1)
        #expect(cache.peek("b") == nil)
        #expect(cache.peek("c") == 3)
        #expect(cache.count == 2)
    }

    @Test func peekDoesNotChangeRecency() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        _ = cache.peek("a")
        cache.insert(3, for: "c")
        #expect(cache.peek("a") == nil)
        #expect(cache.keys == ["b", "c"])
    }

    @Test func reinsertReplacesAndTouches() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.insert(1, for: "a")
        cache.insert(2, for: "b")
        cache.insert(10, for: "a")
        cache.insert(3, for: "c")
        #expect(cache.peek("a") == 10)
        #expect(cache.peek("b") == nil)
    }

    @Test func updateFillsInParts() {
        var cache = LRUCache<String, [Int]>(capacity: 3)
        cache.update("a", default: []) { $0.append(1) }
        cache.update("a", default: []) { $0.append(2) }
        #expect(cache.peek("a") == [1, 2])
    }

    @Test func removal() {
        var cache = LRUCache<Int, Int>(capacity: 5)
        for key in 0..<5 { cache.insert(key, for: key) }
        cache.removeValue(for: 2)
        cache.removeAll { $0.isMultiple(of: 2) }
        #expect(cache.keys == [1, 3])
        cache.removeAll()
        #expect(cache.isEmpty)
    }
}

struct WorkingDiffCacheTests {

    private let diff = DiffResult(filePath: "a.swift", oldPath: nil, isBinary: false, hunks: [], stats: DiffStats(additions: 1, deletions: 0))
    private let entry = StatusEntry(id: "a.swift", path: "a.swift", indexStatus: .unmodified, workdirStatus: .modified)
    private var key: WorkingDiffCache.Key { .init(path: "a.swift", side: .unstaged, ignoreWhitespace: false) }

    @Test func refreshMarksEntriesStaleButKeepsThem() {
        var cache = WorkingDiffCache()
        cache.statusRefreshed([entry])
        cache.store(diff, for: key, status: entry, loadedAt: cache.generation)
        #expect(cache.lookup(key)?.isCurrent == true)
        cache.statusRefreshed([entry])
        #expect(cache.lookup(key)?.isCurrent == false)
    }

    @Test func statusChangeDropsEntry() {
        var cache = WorkingDiffCache()
        cache.store(diff, for: key, status: entry, loadedAt: cache.generation)
        let staged = StatusEntry(id: "a.swift", path: "a.swift", indexStatus: .modified, workdirStatus: .modified)
        cache.statusRefreshed([staged])
        #expect(cache.lookup(key) == nil)
        cache.store(diff, for: key, status: staged, loadedAt: cache.generation)
        cache.statusRefreshed([])
        #expect(cache.isEmpty)
    }

    @Test func loadStartedBeforeRefreshIsStale() {
        var cache = WorkingDiffCache()
        let started = cache.generation
        cache.statusRefreshed([entry])
        cache.store(diff, for: key, status: entry, loadedAt: started)
        #expect(cache.lookup(key)?.isCurrent == false)
    }
}
