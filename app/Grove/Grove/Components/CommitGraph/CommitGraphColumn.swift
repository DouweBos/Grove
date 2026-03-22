// Components/CommitGraph/CommitGraphColumn.swift
// Grove
//
// SwiftUI view that renders the graph topology for a single commit row.
// Uses Canvas for pixel-precise line and circle drawing.

import SwiftUI

// MARK: - Layout Constants

/// Drawing constants shared between CommitGraphColumn and its callers.
enum CommitGraphLayout {
    /// Horizontal width allocated per lane column (points).
    static let laneWidth: CGFloat = 16
    /// Radius of the filled commit circle (points).
    static let circleRadius: CGFloat = 4.5
    /// Stroke width for lane lines and circle outline (points).
    static let lineWidth: CGFloat = 2
    /// Total width for a given number of active columns.
    static func totalWidth(columns: Int) -> CGFloat {
        CGFloat(max(columns, 1)) * laneWidth
    }
}

// MARK: - CommitGraphColumn

/// A fixed-width canvas that paints the commit graph for one row.
///
/// - Vertical lines represent pass-through lanes.
/// - A filled circle marks the commit's own position.
/// - Curved Bezier lines represent merge edges converging from other lanes.
///
/// Callers should size this view to `CommitGraphLayout.totalWidth(columns:)` wide
/// and match the surrounding row height.
struct CommitGraphColumn: View {

    // MARK: Properties

    /// Graph data for this specific commit row.
    let node: GraphNode
    /// Total number of active columns across all visible rows (for fixed width).
    let maxColumns: Int
    /// Height of the containing row — used to position the vertical midpoint.
    var rowHeight: CGFloat = 32

    // MARK: Body

    var body: some View {
        Canvas { context, size in
            let midY = size.height / 2
            drawEdges(in: context, size: size, midY: midY)
            drawCommitCircle(in: context, size: size, midY: midY)
        }
        .frame(
            width: CommitGraphLayout.totalWidth(columns: maxColumns),
            height: rowHeight
        )
    }

    // MARK: - Drawing

    /// Draws all lane edges for this row.
    ///
    /// Three kinds of segments appear in a row:
    ///
    /// 1. **Pass-through** (`fromColumn == toColumn`, column != node.column):
    ///    a full-height straight vertical line in the lane's color.
    ///
    /// 2. **Own-lane** (`fromColumn == toColumn == node.column`):
    ///    split into an above-circle half and a below-circle half so the filled
    ///    circle can be drawn on top cleanly.
    ///
    /// 3. **Merge edge** (`fromColumn == node.column`, `toColumn != node.column`):
    ///    a cubic Bezier starting at the circle's midY and curving down to the
    ///    bottom edge of `toColumn`.
    private func drawEdges(in context: GraphicsContext, size: CGSize, midY: CGFloat) {
        let r = CommitGraphLayout.circleRadius

        for edge in node.edges {
            let fromX = laneCenter(edge.fromColumn)
            let toX   = laneCenter(edge.toColumn)
            var path  = Path()

            let isStraight = edge.fromColumn == edge.toColumn
            let isOwnLane  = isStraight && edge.fromColumn == node.column

            if isStraight {
                if isOwnLane {
                    // Own lane: draw in two segments so the circle sits cleanly
                    // on top of the line without the line bleeding through it.
                    // Segment 1 — top of row → just above circle.
                    path.move(to: CGPoint(x: fromX, y: 0))
                    path.addLine(to: CGPoint(x: fromX, y: midY - r - 1))
                    // Segment 2 — just below circle → bottom of row.
                    path.move(to: CGPoint(x: fromX, y: midY + r + 1))
                    path.addLine(to: CGPoint(x: fromX, y: size.height))
                } else {
                    // Pass-through lane — uninterrupted vertical.
                    path.move(to: CGPoint(x: fromX, y: 0))
                    path.addLine(to: CGPoint(x: fromX, y: size.height))
                }
            } else {
                // Merge edge: Bezier curve from the commit circle (midY)
                // down to the bottom of the target column.
                //
                // Using a cubic Bezier produces a smooth "banana" shape:
                //   control1 keeps the curve near the source column at first,
                //   control2 pulls it toward the target column at the end.
                let startY    = midY
                let endY      = size.height
                let controlY1 = startY + (endY - startY) * 0.5
                let controlY2 = startY + (endY - startY) * 0.7

                path.move(to: CGPoint(x: fromX, y: startY))
                path.addCurve(
                    to: CGPoint(x: toX, y: endY),
                    control1: CGPoint(x: fromX, y: controlY1),
                    control2: CGPoint(x: toX, y: controlY2)
                )
            }

            context.stroke(
                path,
                with: .color(edge.color),
                style: StrokeStyle(lineWidth: CommitGraphLayout.lineWidth, lineCap: .round)
            )
        }
    }

    /// Draws the filled circle that marks the commit's position.
    private func drawCommitCircle(in context: GraphicsContext, size: CGSize, midY: CGFloat) {
        let cx = laneCenter(node.column)
        let r  = CommitGraphLayout.circleRadius

        let circleRect = CGRect(
            x: cx - r,
            y: midY - r,
            width: r * 2,
            height: r * 2
        )
        let circlePath = Path(ellipseIn: circleRect)

        // Fill with the node's primary color.
        context.fill(circlePath, with: .color(node.color))

        // Thin white ring to separate the circle from lines behind it.
        context.stroke(
            circlePath,
            with: .color(.white.opacity(0.6)),
            style: StrokeStyle(lineWidth: 1.5)
        )
    }

    // MARK: - Helpers

    /// Returns the horizontal center point (in points) for a given lane column.
    private func laneCenter(_ column: Int) -> CGFloat {
        CGFloat(column) * CommitGraphLayout.laneWidth + CommitGraphLayout.laneWidth / 2
    }
}

// MARK: - Preview

#Preview("CommitGraphColumn — variety") {
    // Manually construct a handful of representative nodes to visually verify:
    //   row 0: single lane, no parents (root of shown range)
    //   row 1: pass-through + merge edge
    //   row 2: two lanes active
    //   row 3: merge commit with two parents

    let palette = CommitGraphLayout.self
    _ = palette

    let blueColor  = Color(red: 0.20, green: 0.60, blue: 1.00)
    let greenColor = Color(red: 0.18, green: 0.75, blue: 0.45)

    let nodes: [(GraphNode, String)] = [
        (
            GraphNode(
                id: "a",
                column: 0,
                color: blueColor,
                edges: [
                    GraphEdge(fromColumn: 0, toColumn: 0, color: blueColor)
                ],
                isMerge: false
            ),
            "Linear — column 0"
        ),
        (
            GraphNode(
                id: "b",
                column: 0,
                color: blueColor,
                edges: [
                    GraphEdge(fromColumn: 0, toColumn: 0, color: blueColor),
                    GraphEdge(fromColumn: 1, toColumn: 1, color: greenColor)
                ],
                isMerge: false
            ),
            "Pass-through lane 1"
        ),
        (
            GraphNode(
                id: "c",
                column: 0,
                color: blueColor,
                edges: [
                    GraphEdge(fromColumn: 0, toColumn: 0, color: blueColor),
                    GraphEdge(fromColumn: 0, toColumn: 1, color: greenColor)
                ],
                isMerge: true
            ),
            "Merge — main into branch"
        ),
        (
            GraphNode(
                id: "d",
                column: 1,
                color: greenColor,
                edges: [
                    GraphEdge(fromColumn: 0, toColumn: 0, color: blueColor),
                    GraphEdge(fromColumn: 1, toColumn: 1, color: greenColor)
                ],
                isMerge: false
            ),
            "Column 1 commit"
        )
    ]

    return List {
        ForEach(nodes, id: \.0.id) { node, label in
            HStack(spacing: 4) {
                CommitGraphColumn(node: node, maxColumns: 2, rowHeight: 32)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }
    .listStyle(.plain)
    .frame(width: 320, height: 180)
}
