// Blame/BlameLineCell.swift
// GroveUIKit
//
// One blamed line, drawn in one view with no subviews, so 100k lines scroll like ten.

#if os(macOS)
import AppKit
import GroveKit

/// What a row's drawing shares with every other row.
struct BlameDrawing {
    let metrics: BlameMetrics
    let palette: BlamePalette
    let fonts: Fonts

    struct Fonts {
        let code: NSFont
        let gutter: NSFont

        init(_ metrics: BlameMetrics) {
            code = metrics.font
            gutter = metrics.gutterFont
        }
    }

    init(_ style: GitUIStyle) {
        metrics = BlameMetrics(style)
        palette = BlamePalette(style)
        fonts = Fonts(metrics)
    }

    static let uncommittedSHA = String(repeating: "0", count: 40)

    static let dateStyle = Date.FormatStyle.dateTime.year().month(.abbreviated).day()
}

final class BlameLineCell: NSView {
    static let identifier = NSUserInterfaceItemIdentifier("GitBlameLine")

    private var line: BlameLine?
    private var age: CGFloat = 0
    private var drawing: BlameDrawing?

    convenience init() {
        self.init(frame: .zero)
        identifier = Self.identifier
    }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func configure(_ line: BlameLine, age: CGFloat, drawing: BlameDrawing) {
        self.line = line
        self.age = age
        self.drawing = drawing
        if let entry = line.entry, entry.commitSHA != BlameDrawing.uncommittedSHA {
            let date = entry.authorDate.formatted(BlameDrawing.dateStyle)
            toolTip = "\(entry.commitSHA.prefix(7)) \u{00B7} \(entry.authorName) \u{00B7} \(date)\n\(entry.summary)"
        } else {
            toolTip = line.entry == nil ? nil : "Not committed yet"
        }
        setAccessibilityLabel("Line \(line.number): \(line.text)")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let line, let drawing else { return }
        let metrics = drawing.metrics
        let palette = drawing.palette
        let height = bounds.height
        let uncommitted = line.entry?.commitSHA == BlameDrawing.uncommittedSHA
        if line.entry != nil, !uncommitted {
            palette.age(age).setFill()
            NSRect(x: 0, y: 0, width: metrics.annotationWidth, height: height).fill()
        }
        (line.entry.map { uncommitted ? palette.subtle : palette.lane($0.commitSHA) } ?? palette.subtle).setFill()
        NSRect(x: metrics.annotationWidth, y: 0, width: metrics.laneWidth, height: height).fill()
        if line.startsBlock, line.number > 1 {
            palette.border.setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: 0.5).fill()
        }
        if line.startsBlock, let entry = line.entry { drawAnnotation(entry, uncommitted: uncommitted, drawing) }
        let numberX = metrics.annotationWidth + metrics.laneWidth
        text("\(line.number)", in: NSRect(x: numberX, y: 0, width: metrics.numberWidth, height: height),
             font: drawing.fonts.code, color: palette.secondary, alignment: .right)
        let code = line.text.contains("\t") ? line.text.replacingOccurrences(of: "\t", with: "    ") : line.text
        let codeX = metrics.textX
        text(code, in: NSRect(x: codeX, y: 0, width: max(0, bounds.width - codeX), height: height),
             font: drawing.fonts.code, color: palette.text, truncates: false)
    }

    /// The commit's SHA, summary, author and date, Grove's way: SHA in the accent, then left to right.
    private func drawAnnotation(_ entry: BlameEntry, uncommitted: Bool, _ drawing: BlameDrawing) {
        let metrics = drawing.metrics
        let palette = drawing.palette
        let pad = GitMetrics.Spacing.md
        let gap = GitMetrics.Spacing.sm
        let height = bounds.height
        text(uncommitted ? "Uncommitted" : String(entry.commitSHA.prefix(7)),
             in: NSRect(x: pad, y: 0, width: uncommitted ? metrics.shaWidth + 30 : metrics.shaWidth, height: height),
             font: drawing.fonts.code, color: uncommitted ? palette.warning : palette.accent)
        let right = metrics.annotationWidth - pad
        var summaryEnd = right
        if !uncommitted {
            let dateX = right - metrics.dateWidth
            text(entry.authorDate.formatted(BlameDrawing.dateStyle),
                 in: NSRect(x: dateX, y: 0, width: metrics.dateWidth, height: height),
                 font: drawing.fonts.code, color: palette.secondary, alignment: .right)
            let authorX = dateX - gap - metrics.authorWidth
            text(entry.authorName, in: NSRect(x: authorX, y: 0, width: metrics.authorWidth, height: height),
                 font: drawing.fonts.gutter, color: palette.secondary)
            summaryEnd = authorX - gap
        }
        let summaryX = pad + (uncommitted ? metrics.shaWidth + 30 : metrics.shaWidth) + gap
        text(uncommitted ? "Local changes" : entry.summary,
             in: NSRect(x: summaryX, y: 0, width: max(0, summaryEnd - summaryX), height: height),
             font: drawing.fonts.gutter, color: palette.text)
    }

    private func text(_ string: String, in rect: NSRect, font: NSFont, color: NSColor,
                      alignment: NSTextAlignment = .left, truncates: Bool = true) {
        guard rect.width > 0, !string.isEmpty else { return }
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = truncates ? .byTruncatingTail : .byClipping
        style.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let lineHeight = font.ascender - font.descender + font.leading
        let box = NSRect(x: rect.minX, y: ((rect.height - lineHeight) / 2).rounded(), width: rect.width, height: lineHeight)
        (string as NSString).draw(with: box, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                  attributes: attributes)
    }
}

/// Fills a selected line edge to edge with the style's selection.
final class BlameRowView: NSTableRowView {
    var fill: NSColor = .selectedContentBackgroundColor

    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        fill.setFill()
        bounds.fill()
    }

    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}
#endif
