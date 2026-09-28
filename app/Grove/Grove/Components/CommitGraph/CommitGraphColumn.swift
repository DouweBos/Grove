// Components/CommitGraph/CommitGraphColumn.swift
// Grove
//
// Canvas that paints one row of the commit graph: lane lines plus the commit dot.

import SwiftUI

enum CommitGraphLayout {
    static let laneWidth: CGFloat = 14
    static let dotDiameter: CGFloat = 8
    static let lineWidth: CGFloat = 2
    /// Lanes beyond this are clipped so a wide graph can't push the row text away.
    static let maxVisibleLanes = 8

    static func totalWidth(columns: Int) -> CGFloat {
        CGFloat(min(max(columns, 1), maxVisibleLanes)) * laneWidth + laneWidth / 2
    }

    static func laneCenter(_ column: Int) -> CGFloat {
        CGFloat(column) * laneWidth + laneWidth / 2 + 2
    }
}

/// Graph cell for a commit row.
struct CommitGraphColumn: View {
    let node: GraphNode
    let maxColumns: Int
    var isHead = false

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            for line in node.lines {
                context.stroke(path(for: line, height: size.height, midY: midY),
                               with: .color(Theme.laneColor(line.colorIndex)),
                               style: StrokeStyle(lineWidth: CommitGraphLayout.lineWidth, lineCap: .round))
            }
            drawDot(in: context, midY: midY)
        }
        .frame(width: CommitGraphLayout.totalWidth(columns: maxColumns))
        .clipped()
    }

    private func path(for line: GraphLine, height: CGFloat, midY: CGFloat) -> Path {
        let fromX = CommitGraphLayout.laneCenter(line.fromColumn)
        let toX = CommitGraphLayout.laneCenter(line.toColumn)
        var path = Path()
        switch line.kind {
        case .passThrough:
            path.move(to: CGPoint(x: fromX, y: 0))
            path.addLine(to: CGPoint(x: toX, y: height))
        case .incoming:
            path.move(to: CGPoint(x: fromX, y: 0))
            curve(&path, to: CGPoint(x: toX, y: midY), from: CGPoint(x: fromX, y: 0))
        case .outgoing:
            path.move(to: CGPoint(x: fromX, y: midY))
            curve(&path, to: CGPoint(x: toX, y: height), from: CGPoint(x: fromX, y: midY))
        }
        return path
    }

    /// Vertical lines stay straight; lane changes bend with a smooth S-curve.
    private func curve(_ path: inout Path, to end: CGPoint, from start: CGPoint) {
        guard start.x != end.x else { return path.addLine(to: end) }
        let midY = (start.y + end.y) / 2
        path.addCurve(to: end, control1: CGPoint(x: start.x, y: midY), control2: CGPoint(x: end.x, y: midY))
    }

    private func drawDot(in context: GraphicsContext, midY: CGFloat) {
        let d = CommitGraphLayout.dotDiameter
        let rect = CGRect(x: CommitGraphLayout.laneCenter(node.column) - d / 2, y: midY - d / 2, width: d, height: d)
        let dot = Path(ellipseIn: rect)
        let laneColor = Theme.laneColor(node.colorIndex)
        if isHead {
            context.fill(Path(ellipseIn: rect.insetBy(dx: -1, dy: -1)), with: .color(Theme.accent))
        } else if node.isMerge {
            // Hollow dot marks merges; the surface fill hides the lines converging behind it.
            context.fill(dot, with: .color(Theme.surface))
            context.stroke(dot, with: .color(laneColor), lineWidth: CommitGraphLayout.lineWidth)
        } else {
            context.fill(dot, with: .color(laneColor))
        }
    }
}

/// Continues the lanes of the next commit through a non-commit row such as a date header.
struct CommitGraphPassThrough: View {
    let lanes: [GraphLine]
    let maxColumns: Int

    var body: some View {
        Canvas { context, size in
            for line in lanes {
                var path = Path()
                let x = CommitGraphLayout.laneCenter(line.fromColumn)
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(Theme.laneColor(line.colorIndex)), lineWidth: CommitGraphLayout.lineWidth)
            }
        }
        .frame(width: CommitGraphLayout.totalWidth(columns: maxColumns))
        .clipped()
    }
}

#Preview {
    let commits: [CommitInfo] = MockData.commits
    let nodes = CommitGraphBuilder().buildGraph(from: commits)
    let columns = (nodes.map(\.column).max() ?? 0) + 1
    return VStack(spacing: 0) {
        ForEach(nodes.prefix(10)) { node in
            HStack {
                CommitGraphColumn(node: node, maxColumns: columns, isHead: node.id == nodes.first?.id)
                Text(node.id.prefix(7)).font(.monoCaption)
                Spacer()
            }
            .frame(height: 44)
        }
    }
    .frame(width: 260)
    .padding()
    .background(Theme.surface)
}
