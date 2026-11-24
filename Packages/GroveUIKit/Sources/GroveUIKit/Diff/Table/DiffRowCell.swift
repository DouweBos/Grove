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

/// Not generic: Swift 6.3's optimizer crashes on a generic cell's deinit, so each kind is a subclass.
class DiffRowCell: NSView {
    private let rowContent: any DiffRowContent
    private var scrolledX: CGFloat = 0
    private var width: CGFloat = 0

    init(rowContent: any DiffRowContent, identifier: NSUserInterfaceItemIdentifier) {
        self.rowContent = rowContent
        super.init(frame: .zero)
        self.identifier = identifier
        rowContent.clipsToBounds = true
        addSubview(rowContent)
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
        rowContent.place(geometry)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutContent()
    }

    private func layoutContent() {
        let frame = NSRect(x: scrolledX, y: 0, width: width, height: bounds.height)
        if rowContent.frame != frame { rowContent.frame = frame }
    }
}

final class DiffLineCell: DiffRowCell {
    let content = DiffLineView()
    init() { super.init(rowContent: content, identifier: DiffCellID.line) }
}

final class DiffHeaderCell: DiffRowCell {
    let content = DiffHunkHeaderView()
    init() { super.init(rowContent: content, identifier: DiffCellID.header) }
}

final class DiffAnnotationCell: DiffRowCell {
    let content = DiffAnnotationView()
    init() { super.init(rowContent: content, identifier: DiffCellID.annotation) }
}

/// Draws nothing: each line draws its own selection, under its pinned gutter too.
final class DiffRowView: NSTableRowView {
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {}
}
#endif
