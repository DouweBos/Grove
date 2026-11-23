// History/List/CommitListMetrics.swift
// GroveUIKit
//
// The commit table's sizes at the style's zoom, and its colours for AppKit drawing.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

struct CommitListMetrics: Equatable {
    let scale: CGFloat

    init(_ style: GitUIStyle) { scale = style.fontScale }

    var graphRowHeight: CGFloat { (46 * scale).rounded() }
    var tableRowHeight: CGFloat { (26 * scale).rounded() }
    var dayHeight: CGFloat { (28 * scale).rounded() }
    var laneWidth: CGFloat { 14 * scale }
    var dotDiameter: CGFloat { 8 * scale }
    var lineWidth: CGFloat { 2 * scale }
    var avatar: CGFloat { 28 * scale }
    var refNameWidth: CGFloat { 140 * scale }

    func rowHeight(_ layout: HistoryLayout) -> CGFloat { layout == .graph ? graphRowHeight : tableRowHeight }

    func font(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont { .systemFont(ofSize: size * scale, weight: weight) }
    func mono(_ size: CGFloat) -> NSFont { .monospacedSystemFont(ofSize: size * scale, weight: .regular) }

    /// Lanes the graph shows: wide graphs clip, but never below eight and never past a third of the row.
    func visibleLanes(_ columns: Int, width: CGFloat) -> Int {
        min(max(columns, 1), max(8, Int(width / 3 / laneWidth)))
    }

    func graphWidth(lanes: Int) -> CGFloat { CGFloat(lanes) * laneWidth + laneWidth / 2 }
    func laneCenter(_ column: Int) -> CGFloat { CGFloat(column) * laneWidth + laneWidth / 2 + 2 * scale }

    enum Column {
        static let author: CGFloat = 110
        static let date: CGFloat = 92
        static let sha: CGFloat = 62
    }
}

/// The style's colours, dynamic so they resolve in the appearance they draw in.
struct CommitListPalette {
    let text: NSColor
    let secondary: NSColor
    let accent: NSColor
    let success: NSColor
    let info: NSColor
    let warning: NSColor
    let surface: NSColor
    let border: NSColor
    let selection: NSColor
    let lanes: [NSColor]

    init(_ style: GitUIStyle) {
        text = NSColor(style.textPrimary)
        secondary = NSColor(style.textSecondary)
        accent = NSColor(style.accent)
        success = NSColor(style.success)
        info = NSColor(style.info)
        warning = NSColor(style.warning)
        surface = NSColor(style.surface)
        border = NSColor(style.border)
        selection = NSColor(style.selectionFill)
        lanes = style.lanes.map { NSColor($0) }
    }

    func lane(_ index: Int) -> NSColor { lanes.isEmpty ? secondary : lanes[abs(index) % lanes.count] }

    func color(_ kind: CommitDisplayRef.Kind) -> NSColor {
        switch kind {
        case .local(let isHEAD): isHEAD ? accent : success
        case .remote: info
        case .tag: warning
        }
    }
}
#endif
