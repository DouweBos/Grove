// Domain/LRUCache.swift
// GroveKit

import Foundation

/// Small least-recently-used cache for per-item detail panes, keyed by immutable identity.
/// Capacities are tens of entries, so a linear recency list is cheaper than a linked list.
public struct LRUCache<Key: Hashable, Value> {
    let capacity: Int
    private var storage: [Key: Value] = [:]
    /// Least recently used first.
    private var order: [Key] = []

    public init(capacity: Int) {
        precondition(capacity > 0, "LRUCache needs room for at least one entry")
        self.capacity = capacity
    }

    var count: Int { storage.count }
    var isEmpty: Bool { storage.isEmpty }
    var keys: [Key] { order }

    /// Returns the value and marks it as most recently used.
    public mutating func value(for key: Key) -> Value? {
        guard let value = storage[key] else { return nil }
        touch(key)
        return value
    }

    /// Reads without changing recency, e.g. to check whether a prefetch is needed.
    public func peek(_ key: Key) -> Value? {
        storage[key]
    }

    public mutating func insert(_ value: Value, for key: Key) {
        if storage.updateValue(value, forKey: key) != nil {
            touch(key)
            return
        }
        order.append(key)
        if order.count > capacity {
            storage[order.removeFirst()] = nil
        }
    }

    /// Updates an existing entry in place, or inserts `initial` modified by `change`.
    public mutating func update(_ key: Key, default initial: @autoclosure () -> Value, _ change: (inout Value) -> Void) {
        var value = storage[key] ?? initial()
        change(&value)
        insert(value, for: key)
    }

    public mutating func removeValue(for key: Key) {
        guard storage.removeValue(forKey: key) != nil else { return }
        order.removeAll { $0 == key }
    }

    mutating func removeAll(where shouldRemove: (Key) -> Bool) {
        order.removeAll { key in
            guard shouldRemove(key) else { return false }
            storage[key] = nil
            return true
        }
    }

    mutating func removeAll() {
        storage = [:]
        order = []
    }

    private mutating func touch(_ key: Key) {
        guard let index = order.firstIndex(of: key), index != order.count - 1 else { return }
        order.append(order.remove(at: index))
    }
}
