// Views/WorkingCopy/FileSelection.swift
// Grove

import Foundation

/// A file row in the Changes list: a partially staged file has one row per side.
struct FileRow: Hashable {
    let path: String
    let side: DiffSide
}

/// Multi-selection over the Changes list, with Finder-style click, Cmd-click and Shift-click.
struct FileSelection {
    private(set) var rows: Set<FileRow> = []
    /// The row the diff shows: the one clicked or moved to last.
    private(set) var focus: FileRow?
    /// Where Shift-click and Shift-arrow ranges start.
    private var anchor: FileRow?

    var count: Int { rows.count }

    func contains(_ row: FileRow) -> Bool { rows.contains(row) }

    mutating func select(_ row: FileRow) {
        rows = [row]
        focus = row
        anchor = row
    }

    /// `order` is the rows as listed, which ranges follow.
    mutating func click(_ row: FileRow, in order: [FileRow], extend: Bool, toggle: Bool) {
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
    mutating func move(by offset: Int, in order: [FileRow], extend: Bool) {
        guard !order.isEmpty else { return }
        let current = focus.flatMap { order.firstIndex(of: $0) } ?? (offset > 0 ? -1 : order.count)
        let next = order[min(max(current + offset, 0), order.count - 1)]
        if extend { click(next, in: order, extend: true, toggle: false) } else { select(next) }
    }

    /// Keeps each row on the side it still has, following a file to its other side after staging.
    mutating func reconcile(_ place: (FileRow) -> FileRow?) {
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

    private static func range(from start: FileRow, to end: FileRow, in order: [FileRow]) -> [FileRow]? {
        guard let from = order.firstIndex(of: start), let to = order.firstIndex(of: end) else { return nil }
        return Array(order[min(from, to)...max(from, to)])
    }
}
