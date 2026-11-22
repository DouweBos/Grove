// Diff/Table/DiffHunkHeaderView.swift
// GroveUIKit
//
// A hunk's @@ line, and its actions at the trailing edge of what's on screen.

#if os(macOS)
import AppKit
import GroveKit

struct DiffHunkButton: Equatable {
    let title: String
    let action: HunkAction

    static func == (lhs: DiffHunkButton, rhs: DiffHunkButton) -> Bool {
        lhs.title == rhs.title
    }
}

extension HunkAction {
    var isDestructive: Bool { self == .discardHunk || self == .discardLines }
}

final class DiffHunkHeaderView: NSView, DiffRowContent {
    private var header = ""
    private var palette: DiffPalette?
    private var metrics: DiffMetrics?
    private var items: [DiffHunkButton] = []
    private(set) var buttons: [DiffActionButton] = []
    private var perform: ((HunkAction) -> Void)?

    override var isFlipped: Bool { true }

    func configure(header: String, buttons items: [DiffHunkButton], palette: DiffPalette, metrics: DiffMetrics,
                   perform: @escaping (HunkAction) -> Void) {
        self.header = header
        self.palette = palette
        self.metrics = metrics
        self.perform = perform
        setButtons(items)
        for button in buttons { button.configure(palette: palette, metrics: metrics) }
        layoutButtons()
        needsDisplay = true
    }

    func setButtons(_ next: [DiffHunkButton]) {
        guard next != items, let palette, let metrics else { return }
        items = next
        buttons.forEach { $0.removeFromSuperview() }
        buttons = next.map { item in
            let button = DiffActionButton(item)
            button.configure(palette: palette, metrics: metrics)
            button.target = self
            button.action = #selector(tapped(_:))
            addSubview(button)
            return button
        }
        layoutButtons()
        needsDisplay = true
    }

    @objc private func tapped(_ sender: DiffActionButton) {
        perform?(sender.item.action)
    }

    func place(_ geometry: DiffGeometry) {
        layoutButtons()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutButtons()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
        buttons.forEach { $0.needsDisplay = true }
    }

    private func layoutButtons() {
        var x = bounds.width - GitMetrics.Spacing.md
        for button in buttons.reversed() {
            let size = button.intrinsicContentSize
            x -= size.width
            button.frame = NSRect(x: x, y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
            x -= GitMetrics.Spacing.sm
        }
    }

    func isOverButton(_ point: NSPoint) -> Bool {
        buttons.contains { $0.frame.contains(point) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let palette, let metrics else { return }
        palette.headerFill.setFill()
        bounds.fill()
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let end = (buttons.first?.frame.minX ?? bounds.width) - GitMetrics.Spacing.sm
        let height = ceil(metrics.font.ascender - metrics.font.descender + metrics.font.leading)
        let rect = NSRect(x: GitMetrics.Spacing.md, y: ((bounds.height - height) / 2).rounded(),
                          width: max(0, end - GitMetrics.Spacing.md), height: height)
        (header as NSString).draw(
            with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: [.font: metrics.font, .foregroundColor: palette.secondary, .paragraphStyle: paragraph])
    }
}

final class DiffActionButton: NSButton {
    let item: DiffHunkButton
    private var palette: DiffPalette?

    init(_ item: DiffHunkButton) {
        self.item = item
        super.init(frame: .zero)
        title = item.title
        isBordered = false
        setButtonType(.momentaryChange)
        setAccessibilityLabel(item.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(palette: DiffPalette, metrics: DiffMetrics) {
        self.palette = palette
        font = metrics.buttonFont
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    private var textSize: NSSize {
        (title as NSString).size(withAttributes: font.map { [.font: $0] } ?? [:])
    }

    override var intrinsicContentSize: NSSize {
        let size = textSize
        return NSSize(width: ceil(size.width) + GitMetrics.Spacing.sm * 2, height: ceil(size.height) + 6)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if palette?.showsPointingHand == true, isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let palette, let font, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if isHighlighted { context.setAlpha(0.6) }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }
        let destructive = item.action.isDestructive
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25),
                                 xRadius: GitMetrics.Radius.tile, yRadius: GitMetrics.Radius.tile)
        (destructive ? palette.dangerFill : palette.button).setFill()
        shape.fill()
        if !destructive {
            palette.divider.setStroke()
            shape.lineWidth = 0.5
            shape.stroke()
        }
        let size = textSize
        (title as NSString).draw(
            at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: [.font: font, .foregroundColor: destructive ? palette.removed : palette.text])
    }
}
#endif
