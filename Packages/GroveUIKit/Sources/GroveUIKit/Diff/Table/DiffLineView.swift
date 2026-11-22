// Diff/Table/DiffLineView.swift
// GroveUIKit
//
// One line, or a side-by-side pair, drawn directly: no subviews per row.

#if os(macOS)
import AppKit
import GroveKit

/// What a line view draws, besides its palette and geometry.
struct DiffLineContent {
    struct Side {
        let line: DiffLine
        let text: DiffLineText
    }

    let row: DiffRow
    /// The unified line, or a pair's old side.
    let first: Side?
    /// A pair's new side.
    let second: Side?
}

final class DiffLineView: NSView, DiffRowContent {
    private var content: DiffLineContent?
    private var palette: DiffPalette?
    private var geometry: DiffGeometry?

    var isSelected = false {
        didSet { if isSelected != oldValue { needsDisplay = true } }
    }

    /// The characters selected in this row, by dragging along one line.
    var textSelection: DiffTextSelection? {
        didSet { if textSelection != oldValue { needsDisplay = true } }
    }

    /// Where the annotation + shows, while the pointer is over the line.
    var hover: DiffHoverSide? {
        didSet { if hover != oldValue { needsDisplay = true } }
    }

    override var isFlipped: Bool { true }

    func configure(_ content: DiffLineContent, palette: DiffPalette) {
        self.content = content
        self.palette = palette
        needsDisplay = true
    }

    func place(_ geometry: DiffGeometry) {
        let old = self.geometry
        self.geometry = geometry
        if old?.scrolledX != geometry.scrolledX || (geometry.layout == .split && old?.viewport != geometry.viewport) {
            needsDisplay = true
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let content, let palette, let geometry, let context = NSGraphicsContext.current?.cgContext else { return }
        let dirty = dirtyRect.intersection(bounds)
        let drawing = DiffTextDrawing(metrics: geometry.metrics, palette: palette)
        switch content.row.kind {
        case .header, .annotation:
            return
        case .line:
            guard let side = content.first else { return }
            let numbers: [Int?] = switch geometry.gutters {
            case .both: [side.line.oldLineNumber, side.line.newLineNumber]
            case .old: [side.line.oldLineNumber]
            case .new: [side.line.newLineNumber]
            }
            draw(side, numbers: numbers, side: nil, in: bounds, dirty: dirty, drawing: drawing, geometry: geometry, context: context)
        case .pair:
            let half = geometry.half
            let old = NSRect(x: 0, y: 0, width: half, height: bounds.height)
            let new = NSRect(x: half, y: 0, width: max(0, bounds.width - half), height: bounds.height)
            for (side, value, rect) in [(GitDiffLineSide.old, content.first, old), (.new, content.second, new)] {
                if let value {
                    let number = side == .old ? value.line.oldLineNumber : value.line.newLineNumber
                    draw(value, numbers: [number], side: side, in: rect, dirty: dirty, drawing: drawing, geometry: geometry, context: context)
                } else {
                    fill(rect, palette.emptySide, in: context)
                    if isSelected { fill(rect, palette.selection, in: context) }
                }
            }
            fill(NSRect(x: half, y: 0, width: 1, height: bounds.height), palette.divider, in: context)
        }
        if isSelected { fill(NSRect(x: 0, y: 0, width: 3, height: bounds.height), palette.accent, in: context) }
        if let hover { drawAddButton(x: hover == .new ? geometry.half : 0, metrics: geometry.metrics, palette: palette, context: context) }
    }

    private func draw(_ value: DiffLineContent.Side, numbers: [Int?], side: GitDiffLineSide?, in rect: NSRect, dirty: NSRect,
                      drawing: DiffTextDrawing, geometry: DiffGeometry, context: CGContext) {
        let palette = drawing.palette
        let (background, word, signColor, sign): (NSColor?, NSColor, NSColor, String) = switch value.line.type {
        case .addition: (palette.addedFill, palette.addedWord, palette.added, "+")
        case .deletion: (palette.removedFill, palette.removedWord, palette.removed, "\u{2212}")
        case .context: (nil, .clear, palette.secondary, "")
        }
        if let background { fill(rect, background, in: context) }
        if isSelected { fill(rect, palette.selection, in: context) }

        context.saveGState()
        defer { context.restoreGState() }
        context.clip(to: rect)
        var x = rect.minX
        if dirty.minY < geometry.metrics.lineHeight {
            for number in numbers {
                if let number {
                    drawing.draw(String(number), right: x + geometry.gutterWidth - GitMetrics.Spacing.xs, y: 0,
                                 color: palette.secondary, in: context)
                }
                x += geometry.gutterWidth
            }
            if !sign.isEmpty {
                let inset = ((geometry.metrics.signWidth - geometry.metrics.characterWidth) / 2).rounded()
                drawing.draw(sign, left: x + inset, y: 0, color: signColor, in: context)
            }
        }

        // Clipped, not covered, so code scrolls under the pinned gutter on a translucent background too.
        let code = NSRect(x: rect.minX + geometry.textX, y: rect.minY, width: rect.width - geometry.textX, height: rect.height)
        let visible = code.intersection(dirty)
        guard !visible.isEmpty else { return }
        context.clip(to: code)
        let origin = NSPoint(x: code.minX - geometry.scrolledX, y: 0)
        var fills: [(ranges: [NSRange], color: NSColor)] = []
        if !value.text.words.isEmpty { fills.append((value.text.words, word)) }
        if let textSelection, textSelection.side == side {
            fills.append(([textSelection.range], .selectedTextBackgroundColor))
        }
        drawing.draw(value.text, at: origin, visible: visible, color: palette.text, fills: fills, in: context)
    }

    private func fill(_ rect: NSRect, _ color: NSColor, in context: CGContext) {
        context.setFillColor(color.cgColor)
        context.fill(rect)
    }

    private func drawAddButton(x: CGFloat, metrics: DiffMetrics, palette: DiffPalette, context: CGContext) {
        let size = min(metrics.lineHeight - 2, metrics.buttonStrip - 4)
        let rect = NSRect(x: x + 2, y: (metrics.lineHeight - size) / 2, width: size, height: size)
        context.setFillColor(palette.accent.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: GitMetrics.Radius.tile - 2,
                               cornerHeight: GitMetrics.Radius.tile - 2, transform: nil))
        context.fillPath()
        let inset = size * 0.28
        context.setStrokeColor(palette.onAccent.cgColor)
        context.setLineWidth(1.5)
        context.move(to: CGPoint(x: rect.midX, y: rect.minY + inset))
        context.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - inset))
        context.move(to: CGPoint(x: rect.minX + inset, y: rect.midY))
        context.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.midY))
        context.strokePath()
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }

    override func accessibilityValue() -> Any? {
        guard let content else { return nil }
        var sides = [content.first, content.second].compactMap { $0 }
        if case .pair(let left, let right) = content.row.kind, left == right { sides = Array(sides.prefix(1)) }
        return sides.map { side in
            switch side.line.type {
            case .addition: "Added: \(side.line.content)"
            case .deletion: "Removed: \(side.line.content)"
            case .context: side.line.content
            }
        }.joined(separator: "\n")
    }
}
#endif
