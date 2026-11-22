// Diff/Table/DiffNSTableView.swift
// GroveUIKit
//
// The table's events: the gutter's +, option-click, text drags and copy.

#if os(macOS)
import AppKit

final class DiffNSTableView: GitDiffTableView {
    weak var coordinator: DiffTableCoordinator?
    /// Set when the app's scroll view does the vertical scrolling.
    weak var embedded: DiffEmbeddedView?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        let modifiers = event.modifierFlags.intersection([.shift, .command, .control, .option])
        if let coordinator, row >= 0 {
            if modifiers.contains(.option), coordinator.optionClicked(row: row) { return }
            if coordinator.gutterClicked(row: row, x: point.x) { return }
            // The gutter and modified clicks select lines the table's own way.
            if modifiers.isEmpty, let code = coordinator.codeSide(row: row, x: point.x) {
                return trackCode(event, row: row, side: code.side, origin: code.origin, coordinator: coordinator)
            }
        }
        super.mouseDown(with: event)
    }

    private func trackCode(_ event: NSEvent, row: Int, side: GitDiffLineSide?, origin: CGFloat,
                           coordinator: DiffTableCoordinator) {
        guard let window, let text = coordinator.text(inRow: row, side: side) else { return }
        window.makeFirstResponder(self)
        let start = convert(event.locationInWindow, from: nil)
        let anchor = coordinator.textOffset(in: text, row: row, origin: origin, point: start)
        if event.clickCount == 2 {
            coordinator.selectText(row: row, side: side, range: text.word(at: anchor))
            return
        }
        if event.clickCount > 2 {
            coordinator.selectRows(from: row, to: row)
            return
        }
        var drag = CodeDrag(row: row, side: side, origin: origin, text: text, start: start, anchor: anchor)
        var lastDrag: NSEvent?
        NSEvent.startPeriodicEvents(afterDelay: 0.1, withPeriod: 0.05)
        defer { NSEvent.stopPeriodicEvents() }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp, .periodic],
                                          until: .distantFuture, inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp { break }
            if next.type == .leftMouseDragged { lastDrag = next }
            guard let lastDrag else { continue }
            if next.type == .periodic, !autoscroll(with: lastDrag) { continue }
            self.drag(&drag, to: convert(lastDrag.locationInWindow, from: nil))
        }
        if !drag.hasMoved { coordinator.clicked(row: row) }
    }

    /// A drag that began on code.
    struct CodeDrag {
        let row: Int
        let side: GitDiffLineSide?
        let origin: CGFloat
        let text: DiffLineText
        let start: NSPoint
        let anchor: Int
        var hasMoved = false
    }

    /// Along the line selects its text, across lines selects them.
    func drag(_ drag: inout CodeDrag, to point: NSPoint) {
        guard let coordinator else { return }
        if !drag.hasMoved, abs(point.x - drag.start.x) < 3, abs(point.y - drag.start.y) < 3 { return }
        drag.hasMoved = true
        let over = row(nearY: point.y)
        if over == drag.row {
            let offset = coordinator.textOffset(in: drag.text, row: drag.row, origin: drag.origin, point: point)
            coordinator.selectText(row: drag.row, side: drag.side,
                                   range: NSRange(location: min(drag.anchor, offset), length: abs(offset - drag.anchor)))
        } else {
            coordinator.selectRows(from: drag.row, to: over)
        }
    }

    private func row(nearY y: CGFloat) -> Int {
        if y <= 0 { return 0 }
        let row = row(at: NSPoint(x: visibleRect.minX + 1, y: y))
        return row >= 0 ? row : max(0, numberOfRows - 1)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        coordinator?.pointerMoved(row: row(at: point), x: point.x)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        coordinator?.setHover(nil)
    }

    @objc func copy(_ sender: Any?) {
        coordinator?.copyToHost()
    }

    override func scrollToVisible(_ rect: NSRect) -> Bool {
        guard let embedded else { return super.scrollToVisible(rect) }
        return embedded.scrollToVisible(convert(rect, to: embedded))
    }

    override func autoscroll(with event: NSEvent) -> Bool {
        guard let embedded else { return super.autoscroll(with: event) }
        return embedded.autoscroll(with: event)
    }
}
#endif
