// Diff/Table/DiffClipView.swift
// GroveUIKit
//
// Holds the lines on screen still while AppKit trades estimated row heights for real ones. Left to itself it
// offsets twice, for the document's change in height and again for the rows it made.

#if os(macOS)
import AppKit

final class DiffClipView: NSClipView {
    private struct Anchor {
        let row: Int
        /// From the top of what's on screen to the row's.
        let offset: CGFloat
        /// Where that has the clip; somewhere else, and it was moved some way that isn't scrolling.
        let y: CGFloat
    }

    private var anchor: Anchor?
    private var isHolding = false
    private var didResize = false
    /// The lines turned out this much lower than where the clip was sent, for the app's scroll view to follow.
    var onShift: ((CGFloat) -> Void)?

    /// Before rows are replaced or resized on purpose: their old places stop meaning anything.
    func forgetAnchor() {
        anchor = nil
    }

    override func scroll(to newOrigin: NSPoint) {
        // While holding this is AppKit's own correction, and the hold has the last word.
        guard !isHolding, newOrigin.y != bounds.minY else { return super.scroll(to: newOrigin) }
        var origin = newOrigin
        let from = bounds.minY
        // The top has nothing above to move it, and a jump of screens no line to hold on to.
        guard let table = documentView as? NSTableView, origin.y > 0, abs(origin.y - from) < bounds.height * 2 else {
            anchor = nil
            return super.scroll(to: origin)
        }
        let row = table.row(at: NSPoint(x: bounds.minX + 1, y: from + 1))
        guard row >= 0 else {
            anchor = nil
            return super.scroll(to: origin)
        }
        let minY = table.rect(ofRow: row).minY
        // Asking can measure rows, which moves the clip under the request.
        origin.y += bounds.minY - from
        anchor = Anchor(row: row, offset: minY - origin.y, y: origin.y)
        hold(at: origin.y) { super.scroll(to: origin) }
    }

    /// Runs work that can measure rows, then puts the lines back where they were.
    func holdLines(resizing: Bool = false, while work: () -> Void) {
        if isHolding {
            if resizing { didResize = true }
            return work()
        }
        guard let anchor, abs(bounds.minY - anchor.y) < 1 else { return work() }
        hold(at: anchor.y, resized: resizing, while: work)
    }

    private func hold(at y: CGFloat, resized: Bool = false, while work: () -> Void) {
        isHolding = true
        didResize = resized
        defer { isHolding = false }
        work()
        guard didResize, let anchor, let table = documentView as? NSTableView, anchor.row < table.numberOfRows else { return }
        let minY = table.rect(ofRow: anchor.row).minY
        let wanted = max(0, minY - anchor.offset)
        let target = min(wanted, max(0, table.frame.height - bounds.height))
        if bounds.minY != target {
            super.scroll(to: NSPoint(x: bounds.minX, y: target))
            enclosingScrollView?.reflectScrolledClipView(self)
        }
        self.anchor = Anchor(row: anchor.row, offset: minY - target, y: target)
        if abs(wanted - y) >= 0.5 { onShift?(wanted - y) }
    }
}
#endif
