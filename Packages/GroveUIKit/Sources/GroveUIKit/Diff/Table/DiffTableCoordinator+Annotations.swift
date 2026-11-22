// Diff/Table/DiffTableCoordinator+Annotations.swift
// GroveUIKit
//
// The app's rows under lines: the gutter's +, where a card sits, and its popover.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

extension DiffTableCoordinator {

    func annotation(_ index: Int) -> GitDiffAnnotation? {
        guard let items = annotations?.items, items.indices.contains(index) else { return nil }
        return items[index]
    }

    /// Cards line up with the code of their side.
    func cardInset(for annotation: GitDiffAnnotation) -> CGFloat {
        let start = geometry.layout == .split && annotation.side == .new ? geometry.half : 0
        return start + geometry.textX
    }

    /// A card keeps a reading width, and fits inside the pane or its half of it.
    func cardWidth(for annotation: GitDiffAnnotation) -> CGFloat {
        let widest = annotations?.maxWidth ?? 0
        guard geometry.viewport > 0 else { return widest }
        let room = geometry.layout == .split ? geometry.half : geometry.viewport
        return max(200, min(widest, room - geometry.textX - GitMetrics.Spacing.md))
    }

    /// The side of a line row at `x` in what's on screen, if it can take an annotation.
    func side(row: Int, x: CGFloat) -> DiffHoverSide? {
        guard annotations != nil, rows.indices.contains(row) else { return nil }
        switch rows[row].kind {
        case .line:
            return .whole
        case .pair(let left, let right):
            if x >= geometry.half { return right == nil ? nil : .new }
            return left == nil ? nil : .old
        case .header, .annotation:
            return nil
        }
    }

    /// Whether `x` is on that side's + strip.
    func isOnButton(_ side: DiffHoverSide, x: CGFloat) -> Bool {
        let start = side == .new ? geometry.half : 0
        return x >= start && x < start + geometry.metrics.buttonStrip
    }

    func setHover(_ next: (row: Int, side: DiffHoverSide)?) {
        guard next?.row != hover?.row || next?.side != hover?.side else { return }
        hover = next
        forEachVisibleCell { cell, row in
            (cell as? DiffRowCell<DiffLineView>)?.content.hover = next?.row == row ? next?.side : nil
        }
    }

    /// A click on the + opens the composer; anything else is the table's.
    func gutterClicked(row: Int, x: CGFloat) -> Bool {
        let x = x - geometry.scrolledX
        guard let side = side(row: row, x: x), isOnButton(side, x: x) else { return false }
        startAnnotation(row: row, side: side)
        return true
    }

    /// The clicked row, or all of the selection when the row is part of it.
    func pickedLines(row: Int, side: DiffHoverSide) -> GitDiffPickedLines? {
        guard let diff, let table, rows.indices.contains(row) else { return nil }
        let hunk = rows[row].hunk
        var indices = rows[row].lineIndices(side.lineSide)
        let selection = table.selectedRowIndexes
        if selection.contains(row), selection.count > 1 {
            indices = selection
                .filter { rows.indices.contains($0) && rows[$0].hunk == hunk }
                .flatMap { rows[$0].lineIndices(side.lineSide) }
        }
        guard !indices.isEmpty else { return nil }
        return GitDiffPickedLines(hunk: diff.hunks[hunk], indices: indices.sorted(), side: side.lineSide)
    }

    func startAnnotation(row: Int, side: DiffHoverSide) {
        guard let annotations, let picked = pickedLines(row: row, side: side) else { return }
        showPopover(row: row, side: side) { close in annotations.composer(picked, close) }
    }

    func presentPopover(_ content: @escaping (@escaping () -> Void) -> AnyView, overAnnotation id: String) {
        guard let index = annotations?.items.firstIndex(where: { $0.id == id }), let item = annotation(index),
              let row = annotationRows.first(where: { rows[$0].kind == .annotation(index) }) else { return }
        showPopover(row: row, side: geometry.layout == .split && item.side == .new ? .new : .whole) { close in content(close) }
    }

    private func showPopover(row: Int, side: DiffHoverSide, content: (@escaping () -> Void) -> AnyView?) {
        guard let table, table.window != nil else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        guard let view = content({ [weak popover] in popover?.performClose(nil) }) else { return }
        self.popover?.close()
        popover.contentViewController = NSHostingController(rootView: view.environment(\.gitStyle, style))
        let rect = table.rect(ofRow: row)
        let x = geometry.scrolledX + (side == .new ? geometry.half : 0)
        popover.show(
            relativeTo: NSRect(x: x, y: rect.minY, width: geometry.metrics.buttonStrip, height: rect.height),
            of: table, preferredEdge: .maxY)
        self.popover = popover
    }
}
#endif
