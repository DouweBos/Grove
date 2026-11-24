// Blame/BlameMetrics.swift
// GroveUIKit
//
// Blame's sizes at the style's zoom, and its colours for AppKit drawing.

#if os(macOS)
import AppKit
import SwiftUI

struct BlameMetrics: Equatable {
    let scale: CGFloat
    /// The table's visible width; the annotation takes at most 40% of it so the code keeps the rest.
    let available: CGFloat

    init(_ style: GitUIStyle, available: CGFloat = .infinity) {
        scale = style.fontScale
        self.available = available
    }

    var font: NSFont { .monospacedSystemFont(ofSize: 12 * scale, weight: .regular) }
    var gutterFont: NSFont { .systemFont(ofSize: 12 * scale) }
    var lineHeight: CGFloat { (18 * scale).rounded() }
    var charWidth: CGFloat { ("M" as NSString).size(withAttributes: [.font: font]).width }

    /// Who, what and when for a run of lines, left of the lane bar.
    var annotationWidth: CGFloat {
        min(420 * scale, max(150 * scale, available * 0.4)).rounded()
    }
    /// Author and date drop out, in that order, when the annotation narrows.
    var showsAuthor: Bool { annotationWidth >= 400 * scale }
    var showsDate: Bool { annotationWidth >= 240 * scale }
    var laneWidth: CGFloat { 3 }
    var numberWidth: CGFloat { (48 * scale).rounded() }
    var textX: CGFloat { annotationWidth + laneWidth + numberWidth + GitMetrics.Spacing.md }
    var shaWidth: CGFloat { (56 * scale).rounded() }
    var authorWidth: CGFloat { (84 * scale).rounded() }
    var dateWidth: CGFloat { (92 * scale).rounded() }

    /// Wide enough for the longest line; a monospaced line's width is its length.
    func width(longest: Int) -> CGFloat { textX + CGFloat(longest) * charWidth + GitMetrics.Spacing.lg }
}

/// The style's colours, dynamic so they resolve in the appearance they draw in.
struct BlamePalette {
    let text: NSColor
    let secondary: NSColor
    let accent: NSColor
    let warning: NSColor
    let border: NSColor
    let subtle: NSColor
    let selection: NSColor
    let lanes: [NSColor]
    let showsPointingHand: Bool

    init(_ style: GitUIStyle) {
        text = NSColor(style.textPrimary)
        secondary = NSColor(style.textSecondary)
        accent = NSColor(style.accent)
        warning = NSColor(style.warning)
        border = NSColor(style.border)
        subtle = NSColor(style.subtleFill)
        selection = NSColor(style.selectionFill)
        lanes = style.lanes.map { NSColor($0) }
        showsPointingHand = style.showsPointingHand
    }

    /// A commit keeps its colour wherever its lines show up.
    func lane(_ sha: String) -> NSColor {
        guard !lanes.isEmpty else { return secondary }
        let seed = sha.prefix(6).unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return lanes[abs(seed) % lanes.count].withAlphaComponent(0.7)
    }

    /// Newer commits tint their annotation more strongly.
    func age(_ age: CGFloat) -> NSColor { accent.withAlphaComponent(0.03 + 0.12 * age) }
}
#endif
