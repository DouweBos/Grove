// Diff/Table/DiffTableCoordinator+Layout.swift
// GroveUIKit
//
// Follows the width and the sideways scroll, and keeps the top line in place when rows change height.

#if os(macOS)
import AppKit

extension DiffTableCoordinator {

    struct TopAnchor {
        let row: Int
        let offset: CGFloat
    }

    @objc func viewportChanged() {
        guard let clip = scroll?.contentView, clip.bounds.width != geometry.viewport else { return }
        let columns = geometry.wrapColumns
        let anchor = topAnchor()
        geometry.viewport = clip.bounds.width
        fitColumn()
        if geometry.wrapColumns != columns {
            (scroll?.contentView as? DiffClipView)?.forgetAnchor()
            invalidateHeights()
            configureVisible()
            if let anchor { restore(anchor) }
            contentResized()
            return
        }
        placeVisible()
        guard !annotationRows.isEmpty, let table else { return }
        // Cards rewrap with the pane.
        withoutAnimation { table.noteHeightOfRows(withIndexesChanged: annotationRows) }
        forEachVisibleCell { cell, row in
            if cell is DiffRowCell<DiffAnnotationView> { configure(cell, row: row) }
        }
        contentResized()
    }

    @objc func scrolled() {
        guard let clip = scroll?.contentView else { return }
        let x = max(0, clip.bounds.minX)
        guard x != geometry.scrolledX else { return }
        geometry.scrolledX = x
        placeVisible()
    }

    func invalidateHeights() {
        heights.reset()
        guard let table, table.numberOfRows > 0 else { return }
        let all = IndexSet(integersIn: 0..<table.numberOfRows)
        withoutAnimation { table.noteHeightOfRows(withIndexesChanged: all) }
    }

    /// The row at the top of what's on screen, when scrolled off the top.
    func topAnchor() -> TopAnchor? {
        guard embedded == nil, let table, let clip = scroll?.contentView, clip.bounds.minY > 0 else { return nil }
        let row = table.row(at: NSPoint(x: clip.bounds.minX + 1, y: clip.bounds.minY + 1))
        guard row >= 0 else { return nil }
        return TopAnchor(row: row, offset: clip.bounds.minY - table.rect(ofRow: row).minY)
    }

    func restore(_ anchor: TopAnchor) {
        guard let table, let scroll, anchor.row < table.numberOfRows else { return }
        let rect = table.rect(ofRow: anchor.row)
        let clip = scroll.contentView
        let furthest = max(0, table.frame.height - clip.bounds.height)
        let y = min(furthest, rect.minY + min(anchor.offset, max(0, rect.height - 1)))
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y))
        scroll.reflectScrolledClipView(clip)
    }

    func scrollToTop() {
        guard embedded == nil, let scroll, scroll.contentView.bounds.origin != .zero else { return }
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}
#endif
