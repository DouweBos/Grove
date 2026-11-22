// Diff/Engine/DiffMetrics.swift
// GroveUIKit
//
// The sizes every diff row shares; monospaced, so a line's width is its column count.

#if os(macOS)
import AppKit

struct DiffMetrics {
    let scale: CGFloat
    let font: NSFont
    let buttonFont: NSFont
    let lineHeight: CGFloat
    let headerHeight: CGFloat
    /// From a line's top to its text's baseline.
    let baseline: CGFloat
    let characterWidth: CGFloat
    let signWidth: CGFloat
    /// The strip at a line's (or a split side's) leading edge where the annotation button sits.
    let buttonStrip: CGFloat

    init(scale: CGFloat) {
        self.scale = scale
        let font = NSFont.monospacedSystemFont(ofSize: 12 * scale, weight: .regular)
        self.font = font
        buttonFont = .systemFont(ofSize: 11 * scale, weight: .medium)
        let textHeight = font.ascender - font.descender
        lineHeight = max((17 * scale).rounded(), ceil(textHeight))
        headerHeight = (32 * scale).rounded()
        baseline = ((lineHeight - textHeight) / 2 + font.ascender).rounded()
        characterWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        signWidth = (16 * scale).rounded()
        buttonStrip = (20 * scale).rounded()
    }

    func gutterWidth(digits: Int) -> CGFloat {
        max((40 * scale).rounded(), ceil(CGFloat(digits) * characterWidth)) + GitMetrics.Spacing.xs
    }
}

/// Where a row's parts go for the table's current layout and width.
struct DiffGeometry {
    let metrics: DiffMetrics
    var layout: GitDiffLayout = .inline
    var gutters = DiffGutters.both
    var gutterWidth: CGFloat
    var wraps = false
    /// The width on screen; zero before the first layout.
    var viewport: CGFloat = 0
    /// How far the diff is scrolled sideways.
    var scrolledX: CGFloat = 0

    init(metrics: DiffMetrics) {
        self.metrics = metrics
        gutterWidth = metrics.gutterWidth(digits: 1)
    }

    var half: CGFloat { floor(viewport / 2) }

    /// The gutters and sign in front of a line's text, from its side's leading edge.
    var textX: CGFloat {
        gutterWidth * CGFloat(layout == .inline ? gutters.count : 1) + metrics.signWidth
    }

    /// Columns before a line wraps; nil when lines don't wrap or the width isn't known yet.
    var wrapColumns: Int? {
        guard wraps, viewport > 0 else { return nil }
        let room = layout == .inline
            ? viewport - textX - GitMetrics.Spacing.lg
            : half - textX - GitMetrics.Spacing.sm
        return max(8, Int(room / metrics.characterWidth))
    }

    /// The document's least width.
    func contentWidth(columns: Int) -> CGFloat {
        guard layout == .inline, !wraps else { return 0 }
        return ceil(textX + CGFloat(columns) * metrics.characterWidth + GitMetrics.Spacing.xl)
    }

    /// Unwrapped lines draw a little past the screen so a drag of the pane doesn't redraw every row each step.
    var lineWidth: CGFloat {
        guard layout == .inline, !wraps else { return viewport }
        return ceil(viewport / 512) * 512
    }
}
#endif
