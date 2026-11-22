// DiffFixtures.swift
// GroveUIKitTests

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI
import Testing
@testable import GroveUIKit

enum DiffFixture {
    /// One hunk per string, a line per character: "-" deleted, "+" added, else context.
    static func diff(_ hunks: [String], path: String = "a.txt", content: (Int) -> String = { "line \($0)" }) -> DiffResult {
        var old = 1
        var new = 1
        let built = hunks.enumerated().map { h, types in
            let lines = types.enumerated().map { i, type -> DiffLine in
                let id = "\(path)-\(types)-\(h)-\(i)"
                switch type {
                case "-":
                    defer { old += 1 }
                    return DiffLine(id: id, type: .deletion, content: content(i), oldLineNumber: old)
                case "+":
                    defer { new += 1 }
                    return DiffLine(id: id, type: .addition, content: content(i), newLineNumber: new)
                default:
                    defer { old += 1; new += 1 }
                    return DiffLine(id: id, type: .context, content: content(i), oldLineNumber: old, newLineNumber: new)
                }
            }
            return HunkData(id: "\(path)-\(types)-\(h)", header: "@@ \(h) @@", oldStart: 1, oldCount: 1, newStart: 1, newCount: 1, lines: lines)
        }
        return DiffResult(filePath: path, hunks: built, stats: DiffStats(additions: 0, deletions: 0))
    }
}

/// A table in a window that never shows, fed as SwiftUI would.
@MainActor
final class DiffTableProbe {
    let coordinator = DiffTableCoordinator()
    let window: NSWindow
    let root: NSView
    private(set) var copied: [String] = []
    private(set) var opened: [(path: String, line: Int?)] = []
    private(set) var acted: [(action: HunkAction, hunk: HunkData, lines: [DiffLine])] = []

    init(size: NSSize = NSSize(width: 800, height: 600), fitsContent: Bool = false) {
        root = coordinator.makeView(fitsContent: fitsContent)
        window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -8000, y: -8000), size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        guard !fitsContent else { return }
        window.contentView = root
        layout()
    }

    var table: DiffNSTableView {
        get throws { try #require(coordinator.table) }
    }

    func show(_ diff: DiffResult, layout shape: GitDiffLayout = .inline, wraps: Bool = false, side: DiffSide? = nil,
              annotations: GitDiffAnnotations? = nil, style: GitUIStyle = .system, opens: Bool = false) {
        var input = DiffTableInput(diff: diff, layout: shape, wrapsLines: wraps, annotations: annotations, style: style)
        if let side {
            input.staging = GitDiffStaging(side: side) { [weak self] action, hunk, lines in
                self?.acted.append((action, hunk, lines))
            }
        }
        input.host = GitUIHost(copy: { [weak self] text in self?.copied.append(text) })
        if opens { input.host.openFile = { [weak self] path, line in self?.opened.append((path, line)) } }
        coordinator.update(input)
        layout()
    }

    func layout() {
        window.contentView?.layoutSubtreeIfNeeded()
        coordinator.table?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    func select(_ rows: IndexSet) throws {
        try table.selectRowIndexes(rows, byExtendingSelection: false)
    }

    func cell<Content: DiffRowContent>(_ row: Int, _: Content.Type) throws -> Content {
        let cell = try table.view(atColumn: 0, row: row, makeIfNecessary: true) as? DiffRowCell<Content>
        return try #require(cell).content
    }

    func buttons(_ row: Int = 0) throws -> [String] {
        try cell(row, DiffHunkHeaderView.self).buttons.map(\.title)
    }

    func close() {
        coordinator.close()
        window.close()
    }
}
#endif
