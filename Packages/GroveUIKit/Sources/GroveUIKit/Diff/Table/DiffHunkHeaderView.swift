// Diff/Table/DiffHunkHeaderView.swift
// GroveUIKit
//
// A hunk's @@ line, and its actions at the trailing edge of what's on screen.

#if os(macOS)
import AppKit
import CoreText
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
    private var headerLine: CTLine?

    override var isFlipped: Bool { true }

    func configure(header: String, buttons items: [DiffHunkButton], palette: DiffPalette, metrics: DiffMetrics,
                   perform: @escaping (HunkAction) -> Void) {
        self.header = header
        self.palette = palette
        self.metrics = metrics
        self.perform = perform
        headerLine = nil
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
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let end = (buttons.first?.frame.minX ?? bounds.width) - GitMetrics.Spacing.sm
        let room = max(0, end - GitMetrics.Spacing.md)
        // Core Text, kept: laying the string out again on every step of a resize is a stutter.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: metrics.font, NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
        let line = headerLine ?? CTLineCreateWithAttributedString(NSAttributedString(string: header, attributes: attributes))
        headerLine = line
        var shown: CTLine? = line
        if CTLineGetTypographicBounds(line, nil, nil, nil) > Double(room) {
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "\u{2026}", attributes: attributes))
            shown = CTLineCreateTruncatedLine(line, Double(room), .end, ellipsis)
        }
        guard let shown else { return }
        context.setFillColor(palette.secondary.cgColor)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        let top = ((bounds.height - metrics.lineHeight) / 2).rounded()
        context.textPosition = CGPoint(x: GitMetrics.Spacing.md, y: top + metrics.baseline)
        CTLineDraw(shown, context)
    }
}

final class DiffActionButton: NSButton {
    let item: DiffHunkButton
    private var palette: DiffPalette?
    private var textSize = NSSize.zero

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
        // Setting the font re-lays out a button's cell, so only when it changed.
        if font != metrics.buttonFont || textSize == .zero {
            font = metrics.buttonFont
            textSize = (title as NSString).size(withAttributes: [.font: metrics.buttonFont])
        }
        needsDisplay = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(textSize.width) + GitMetrics.Spacing.sm * 2, height: ceil(textSize.height) + 6)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if palette?.showsPointingHand == true, isEnabled { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let palette, let font, let context = NSGraphicsContext.current?.cgContext else { return }
        // Only a pressed button pays for a layer to fade as one.
        let dims = isHighlighted
        if dims {
            context.saveGState()
            context.setAlpha(0.6)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
        }
        defer {
            if dims {
                context.endTransparencyLayer()
                context.restoreGState()
            }
        }
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
