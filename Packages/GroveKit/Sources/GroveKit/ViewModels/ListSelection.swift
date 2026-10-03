// ViewModels/ListSelection.swift
// GroveKit

import Foundation

/// Multi-selection over a list, with Finder-style click, Cmd-click and Shift-click.
public struct ListSelection<Row: Hashable> {
    public private(set) var rows: Set<Row> = []
    /// The row the detail pane shows: the one clicked or moved to last.
    private(set) var focus: Row?
    /// Where Shift-click and Shift-arrow ranges start.
    private var anchor: Row?

    public var count: Int { rows.count }

    public func contains(_ row: Row) -> Bool { rows.contains(row) }

    public mutating func select(_ row: Row) {
        rows = [row]
        focus = row
        anchor = row
    }

    /// `order` is the rows as listed, which ranges follow.
    mutating func click(_ row: Row, in order: [Row], extend: Bool, toggle: Bool) {
        if extend, let anchor, let range = Self.range(from: anchor, to: row, in: order) {
            rows = toggle ? rows.union(range) : Set(range)
            focus = row
        } else if toggle {
            if rows.contains(row) {
                rows.remove(row)
                focus = rows.contains(focus ?? row) ? focus : rows.first
            } else {
                rows.insert(row)
                focus = row
            }
            anchor = row
        } else {
            select(row)
        }
    }

    /// Arrow keys: move the focus, or with Shift grow the range from the anchor.
    mutating func move(by offset: Int, in order: [Row], extend: Bool) {
        guard !order.isEmpty else { return }
        let current = focus.flatMap { order.firstIndex(of: $0) } ?? (offset > 0 ? -1 : order.count)
        let next = order[min(max(current + offset, 0), order.count - 1)]
        if extend { click(next, in: order, extend: true, toggle: false) } else { select(next) }
    }

    /// Maps rows to where they are now after the list changed, dropping those `place` returns nil for.
    mutating func reconcile(_ place: (Row) -> Row?) {
        rows = Set(rows.compactMap(place))
        focus = focus.flatMap(place)
        anchor = anchor.flatMap(place)
        if focus == nil { focus = rows.first }
    }

    mutating func clear() {
        rows = []
        focus = nil
        anchor = nil
    }

    private static func range(from start: Row, to end: Row, in order: [Row]) -> [Row]? {
        guard let from = order.firstIndex(of: start), let to = order.firstIndex(of: end) else { return nil }
        return Array(order[min(from, to)...max(from, to)])
    }
}
