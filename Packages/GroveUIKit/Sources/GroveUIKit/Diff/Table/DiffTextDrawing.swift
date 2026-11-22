// Diff/Table/DiffTextDrawing.swift
// GroveUIKit
//
// A line's text through Core Text: only the part on screen, with colors resolved as it draws.

#if os(macOS)
import AppKit
import CoreText

struct DiffTextDrawing {
    let metrics: DiffMetrics
    let palette: DiffPalette

    /// Where a piece of text draws, from its line's text origin.
    struct Piece {
        let range: NSRange
        let x: CGFloat
        let y: CGFloat
    }

    /// Past this a piece is drawn only where it's on screen.
    private static let longLine = 512

    /// The pieces in `visible`, which is measured from the text's origin.
    func pieces(_ text: DiffLineText, visible: NSRect) -> [Piece] {
        guard text.text.length > 0 else { return [] }
        let first = max(0, Int(floor(visible.minY / metrics.lineHeight)))
        let last = min(text.lineCount - 1, Int(floor(visible.maxY / metrics.lineHeight)))
        guard first <= last else { return [] }
        return (first...last).map { line in
            var range = text.range(ofLine: line)
            var x: CGFloat = 0
            // ASCII in a monospaced font: columns are offsets.
            if range.length > Self.longLine, text.isASCII {
                let from = min(range.length, max(0, Int(visible.minX / metrics.characterWidth) - 2))
                let to = min(range.length, max(from, Int(visible.maxX / metrics.characterWidth) + 2))
                range = NSRange(location: range.location + from, length: to - from)
                x = CGFloat(from) * metrics.characterWidth
            }
            return Piece(range: range, x: x, y: CGFloat(line) * metrics.lineHeight)
        }
    }

    /// - Parameters:
    ///   - origin: The text's top left in the flipped view.
    ///   - fills: Backgrounds behind ranges of it, e.g. changed words and the selection.
    func draw(_ text: DiffLineText, at origin: NSPoint, visible: NSRect, color: NSColor,
              fills: [(ranges: [NSRange], color: NSColor)], in context: CGContext) {
        for piece in pieces(text, visible: visible.offsetBy(dx: -origin.x, dy: -origin.y)) {
            let line = line(text, range: piece.range, color: color)
            let x = origin.x + piece.x
            let y = origin.y + piece.y
            for fill in fills {
                for range in fill.ranges {
                    let shown = NSIntersectionRange(range, piece.range)
                    guard shown.length > 0 else { continue }
                    let from = CTLineGetOffsetForStringIndex(line, shown.location - piece.range.location, nil)
                    let to = CTLineGetOffsetForStringIndex(line, NSMaxRange(shown) - piece.range.location, nil)
                    context.setFillColor(fill.color.cgColor)
                    context.fill(CGRect(x: x + from, y: y, width: to - from, height: metrics.lineHeight))
                }
            }
            draw(line, x: x, y: y, in: context)
        }
    }

    /// One short string, e.g. a line number, ending at `right` or starting at `left`.
    func draw(_ string: String, left: CGFloat? = nil, right: CGFloat? = nil, y: CGFloat, color: NSColor, in context: CGContext) {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes(color)))
        let x = left ?? (right ?? 0) - CGFloat(string.utf8.count) * metrics.characterWidth
        draw(line, x: x, y: y, in: context)
    }

    private func draw(_ line: CTLine, x: CGFloat, y: CGFloat, in context: CGContext) {
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: x, y: y + metrics.baseline)
        CTLineDraw(line, context)
    }

    private func attributes(_ color: NSColor) -> [NSAttributedString.Key: Any] {
        [.font: metrics.font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor]
    }

    private func line(_ text: DiffLineText, range: NSRange, color: NSColor) -> CTLine {
        CTLineCreateWithAttributedString(attributed(text, range: range, color: color))
    }

    func attributed(_ text: DiffLineText, range: NSRange, color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text.text.substring(with: range), attributes: attributes(color))
        let key = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        for token in text.tokens {
            guard token.range.location < NSMaxRange(range) else { break }
            let shown = NSIntersectionRange(token.range, range)
            guard shown.length > 0 else { continue }
            result.addAttribute(key, value: palette.color(token.kind).cgColor,
                                range: NSRange(location: shown.location - range.location, length: shown.length))
        }
        return result
    }

    /// The display offset under a point measured from the text's origin.
    func offset(in text: DiffLineText, at point: NSPoint) -> Int {
        let line = min(max(0, Int(floor(point.y / metrics.lineHeight))), text.lineCount - 1)
        let range = text.range(ofLine: line)
        guard point.x > 0, range.length > 0 else { return range.location }
        if text.isASCII {
            return range.location + min(range.length, Int((point.x / metrics.characterWidth).rounded()))
        }
        let index = CTLineGetStringIndexForPosition(self.line(text, range: range, color: palette.text), point)
        return range.location + min(max(index, 0), range.length)
    }
}
#endif
