// Diff/Engine/DiffRows.swift
// GroveUIKit
//
// Flattens a diff into rows once, so the table only looks rows up.

#if os(macOS)
import Foundation
import GroveKit

/// The unified layout's line-number gutters: a new file's lines have no old numbers, a deleted file's
/// no new ones, so it drops the empty gutter.
nonisolated enum DiffGutters: Equatable {
    case both
    case old
    case new

    var count: Int { self == .both ? 2 : 1 }
}

/// A hunk header, a line (inline), a pair of lines (split) or the app's row under one.
/// Indices point into `DiffResult.hunks[hunk].lines`.
nonisolated struct DiffRow: Hashable {
    enum Kind: Hashable {
        case header
        case line(Int)
        case pair(left: Int?, right: Int?)
        /// An index into the annotations the rows were built with.
        case annotation(Int)

        var isSelectable: Bool {
            switch self {
            case .line, .pair: true
            case .header, .annotation: false
            }
        }
    }

    let hunk: Int
    let kind: Kind

    /// The hunk's lines this row shows on `side`, or on either.
    func lineIndices(_ side: GitDiffLineSide? = nil) -> [Int] {
        switch kind {
        case .line(let index): [index]
        case .pair(let left, let right):
            switch side {
            case .old: left.map { [$0] } ?? []
            case .new: right.map { [$0] } ?? []
            case nil: left == right ? (left.map { [$0] } ?? []) : [left, right].compactMap { $0 }
            }
        case .header, .annotation: []
        }
    }
}

nonisolated struct DiffPlacement: Equatable {
    let annotation: Int
    let hunk: Int
    let line: Int
}

nonisolated enum DiffRowBuilder {

    static func rows(for diff: DiffResult, layout: GitDiffLayout, placements: [DiffPlacement] = []) -> [DiffRow] {
        build(diff, layout: layout, placements: placements).rows
    }

    /// The rows, and where each hunk's begin.
    static func build(_ diff: DiffResult, layout: GitDiffLayout,
                      placements: [DiffPlacement] = []) -> (rows: [DiffRow], starts: [Int], annotated: IndexSet) {
        let hunks = diff.hunks
        var rows: [DiffRow] = []
        var starts: [Int] = []
        var annotated = IndexSet()
        var capacity = placements.count + hunks.count
        for hunk in hunks { capacity += hunk.lines.count }
        rows.reserveCapacity(capacity)
        starts.reserveCapacity(hunks.count)
        let byHunk = Dictionary(grouping: placements, by: \.hunk)
        for (h, hunk) in hunks.enumerated() {
            starts.append(rows.count)
            rows.append(DiffRow(hunk: h, kind: .header))
            let under = byHunk[h].map { Dictionary(grouping: $0, by: \.line) }
            // Looked up per line: a dictionary's hashing would double a big diff's build.
            var hasAnnotation = under == nil ? [] : [Bool](repeating: false, count: hunk.lines.count)
            if let under { for line in under.keys where hasAnnotation.indices.contains(line) { hasAnnotation[line] = true } }
            func addAnnotations(_ line: Int?) {
                guard let line, hasAnnotation[line], let placed = under?[line] else { return }
                for placement in placed {
                    annotated.insert(rows.count)
                    rows.append(DiffRow(hunk: h, kind: .annotation(placement.annotation)))
                }
            }
            switch layout {
            case .inline:
                var index = 0
                while index < hunk.lines.count {
                    rows.append(DiffRow(hunk: h, kind: .line(index)))
                    if under != nil, hasAnnotation[index] { addAnnotations(index) }
                    index += 1
                }
            case .split:
                forEachPair(hunk.lines) { left, right in
                    rows.append(DiffRow(hunk: h, kind: .pair(left: left, right: right)))
                    if under != nil {
                        addAnnotations(left)
                        if right != left { addAnnotations(right) }
                    }
                }
            }
        }
        return (rows, starts, annotated)
    }

    /// Context lines sit on both sides; a run of deletions pairs up with the run of additions after it,
    /// the longer run leaving blanks opposite.
    static func forEachPair(_ lines: [DiffLine], _ body: (Int?, Int?) -> Void) {
        var i = 0
        while i < lines.count {
            if lines[i].type == .context {
                body(i, i)
                i += 1
                continue
            }
            let deletions = i
            while i < lines.count, lines[i].type == .deletion { i += 1 }
            let additions = i
            while i < lines.count, lines[i].type == .addition { i += 1 }
            let removed = additions - deletions
            let added = i - additions
            var k = 0
            while k < max(removed, added) {
                body(k < removed ? deletions + k : nil, k < added ? additions + k : nil)
                k += 1
            }
        }
    }

    static func pairs(_ lines: [DiffLine]) -> [(Int?, Int?)] {
        var result: [(Int?, Int?)] = []
        forEachPair(lines) { result.append(($0, $1)) }
        return result
    }

    /// For each changed line the one across from it, or -1: whose words to compare.
    static func partners(_ lines: [DiffLine]) -> [Int] {
        var result = [Int](repeating: -1, count: lines.count)
        forEachPair(lines) { left, right in
            guard let left, let right, left != right else { return }
            result[left] = right
            result[right] = left
        }
        return result
    }

    /// Only additions or only deletions: nothing to set side by side, so even the split layout shows one column.
    static func isOneSided(_ diff: DiffResult) -> Bool {
        var additions = false
        var deletions = false
        for hunk in diff.hunks {
            for line in hunk.lines {
                if line.type == .addition { additions = true }
                if line.type == .deletion { deletions = true }
                if additions && deletions { return false }
            }
        }
        return true
    }

    static func gutters(for diff: DiffResult) -> DiffGutters {
        let lines = diff.hunks.lazy.flatMap(\.lines)
        if !lines.contains(where: { $0.oldLineNumber != nil }) { return .new }
        if !lines.contains(where: { $0.newLineNumber != nil }) { return .old }
        return .both
    }

    /// The longest line in columns, rounded up for non-ASCII, for the width to scroll sideways.
    static func widestLine(in diff: DiffResult) -> Int {
        var widest = 0
        for hunk in diff.hunks {
            for line in hunk.lines {
                var content = line.content
                let columns = content.withUTF8 { bytes in
                    guard let base = bytes.baseAddress, !bytes.isEmpty else { return 0 }
                    // memchr: a per-byte loop over 100k lines is a pause in a debug build.
                    var tabs = 0
                    var from = 0
                    while from < bytes.count, let found = memchr(base + from, 0x09, bytes.count - from) {
                        tabs += 1
                        from = UnsafeRawPointer(found) - UnsafeRawPointer(base) + 1
                    }
                    return bytes.count + tabs * (DiffLineText.tab.count - 1)
                }
                if columns > widest { widest = columns }
            }
        }
        return widest
    }

    /// How many digits the diff's largest line number has.
    static func numberDigits(in diff: DiffResult) -> Int {
        var largest = 0
        for hunk in diff.hunks {
            for line in hunk.lines.suffix(2) {
                largest = max(largest, line.oldLineNumber ?? 0, line.newLineNumber ?? 0)
            }
        }
        return String(largest).count
    }
}
#endif
