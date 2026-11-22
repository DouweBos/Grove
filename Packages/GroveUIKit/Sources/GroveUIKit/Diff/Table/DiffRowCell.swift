// Diff/Table/DiffRowCell.swift
// GroveUIKit
//
// A row's cell holds one view no wider than the screen, so gutters and headers stay put while code scrolls
// sideways and a long line doesn't cost a bitmap as long as itself.

#if os(macOS)
import AppKit

protocol DiffRowContent: NSView {
    /// The table's layout, width or sideways scroll changed.
    func place(_ geometry: DiffGeometry)
}

final class DiffRowCell<Content: DiffRowContent>: NSView {
    let content: Content
    private var scrolledX: CGFloat = 0
    private var width: CGFloat = 0

    init(content: Content, identifier: NSUserInterfaceItemIdentifier) {
        self.content = content
        super.init(frame: .zero)
        self.identifier = identifier
        content.clipsToBounds = true
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    // No drawing of its own: the cell can be as wide as the longest line.
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}

    func place(_ geometry: DiffGeometry, width: CGFloat) {
        scrolledX = geometry.scrolledX
        self.width = width
        layoutContent()
        content.place(geometry)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContent()
    }

    private func layoutContent() {
        let frame = NSRect(x: scrolledX, y: 0, width: width, height: bounds.height)
        if content.frame != frame { content.frame = frame }
    }
}

/// Draws nothing: each line draws its own selection, under its pinned gutter too.
final class DiffRowView: NSTableRowView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}
}
#endif
