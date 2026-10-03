// Views/Stack/StackTreeLayout.swift
// Grove
//
// Rows and lane connectors for a stack drawn like History: tips on top, trunk at the bottom, a split in its own lane.

import GroveKit
import SwiftUI

/// Where each layer sits and which connector pieces its row draws.
nonisolated struct StackTreeLayout: Equatable, Sendable {

    /// A connector piece in one row's gutter.
    enum Segment: Hashable, Sendable {
        /// Line through the whole row in a lane.
        case through(Int)
        /// From the row's top down to its node.
        case top(Int)
        /// From the node down to the row's bottom.
        case bottom(Int)
        /// From one lane at node height across into another, then down.
        case join(from: Int, to: Int)
    }

    struct Row: Identifiable, Equatable, Sendable {
        var id: String { branch }
        let branch: String
        let lane: Int
        var segments: [Segment]
    }

    let rows: [Row]
    let laneCount: Int
    /// Lanes that carry on into the trunk row below the last layer.
    let trunkLanes: [Int]

    /// The first child keeps its parent's lane; each further child opens the next free lane.
    init(_ stack: BranchStack) {
        var lanes: [String: Int] = [:]
        var nextLane = 0
        for layer in stack.layers {
            if let parent = layer.parent, let parentLane = lanes[parent] {
                let siblings = stack.children(of: parent)
                if siblings.first?.branch == layer.branch {
                    lanes[layer.branch] = parentLane
                } else {
                    lanes[layer.branch] = nextLane
                    nextLane += 1
                }
            } else {
                lanes[layer.branch] = nextLane
                nextLane += 1
            }
        }
        // Children above parents: the reverse of topological order.
        let ordered = Array(stack.layers.reversed())
        let position = Dictionary(ordered.enumerated().map { ($1.branch, $0) }, uniquingKeysWith: { first, _ in first })
        var rows = ordered.map { Row(branch: $0.branch, lane: lanes[$0.branch] ?? 0, segments: []) }
        var trunkLanes: [Int] = []
        for layer in ordered {
            guard let row = position[layer.branch] else { continue }
            let lane = rows[row].lane
            rows[row].segments.append(.bottom(lane))
            guard let parent = layer.parent, let parentRow = position[parent] else {
                // A root runs on down to trunk.
                for below in (row + 1)..<rows.count { rows[below].segments.append(.through(lane)) }
                trunkLanes.append(lane)
                continue
            }
            for between in (row + 1)..<parentRow { rows[between].segments.append(.through(lane)) }
            let parentLane = rows[parentRow].lane
            rows[parentRow].segments.append(parentLane == lane ? .top(lane) : .join(from: lane, to: parentLane))
        }
        self.rows = rows.map { row in
            var unique: [Segment] = []
            for segment in row.segments where !unique.contains(segment) { unique.append(segment) }
            return Row(branch: row.branch, lane: row.lane, segments: unique)
        }
        laneCount = max(1, nextLane)
        self.trunkLanes = trunkLanes.sorted()
    }
}

/// Draws one row's connector pieces and its node.
struct StackLaneGutter: View {
    let segments: [StackTreeLayout.Segment]
    /// nil for the trunk row, which only draws incoming lanes.
    let lane: Int?
    let laneCount: Int
    var isHEAD = false
    /// Node height from the row's top, level with the card's title.
    static let nodeY: CGFloat = 22
    static let laneWidth: CGFloat = 16

    var body: some View {
        Canvas { context, size in
            func x(_ lane: Int) -> CGFloat { CGFloat(lane) * Self.laneWidth + Self.laneWidth / 2 }
            func stroke(_ path: Path, _ lane: Int) {
                context.stroke(path, with: .color(Theme.laneColor(lane)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            let y = Self.nodeY
            for segment in segments {
                var path = Path()
                switch segment {
                case .through(let lane):
                    path.move(to: CGPoint(x: x(lane), y: 0)); path.addLine(to: CGPoint(x: x(lane), y: size.height))
                    stroke(path, lane)
                case .top(let lane):
                    path.move(to: CGPoint(x: x(lane), y: 0)); path.addLine(to: CGPoint(x: x(lane), y: y))
                    stroke(path, lane)
                case .bottom(let lane):
                    path.move(to: CGPoint(x: x(lane), y: y)); path.addLine(to: CGPoint(x: x(lane), y: size.height))
                    stroke(path, lane)
                case .join(let from, let to):
                    path.move(to: CGPoint(x: x(from), y: 0))
                    path.addLine(to: CGPoint(x: x(from), y: y - 8))
                    path.addQuadCurve(to: CGPoint(x: x(to), y: y), control: CGPoint(x: x(from), y: y))
                    stroke(path, from)
                }
            }
            if let lane {
                let dot = CGRect(x: x(lane) - 5, y: y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: dot), with: .color(Theme.laneColor(lane)))
                if isHEAD {
                    context.stroke(Path(ellipseIn: dot.insetBy(dx: -3, dy: -3)), with: .color(Theme.laneColor(lane)), lineWidth: 1.5)
                }
            }
        }
        .frame(width: CGFloat(laneCount) * Self.laneWidth)
    }
}

#Preview("Split") {
    let layout = StackTreeLayout(MockData.splitStack)
    return VStack(spacing: 0) {
        ForEach(layout.rows) { row in
            HStack {
                StackLaneGutter(segments: row.segments, lane: row.lane, laneCount: layout.laneCount)
                Text(row.branch).font(.monoCaption)
                Spacer()
            }
            .frame(height: 44)
        }
        HStack {
            StackLaneGutter(segments: layout.trunkLanes.map { .top($0) }, lane: nil, laneCount: layout.laneCount)
            Text("main").font(.monoCaption)
            Spacer()
        }
        .frame(height: 30)
    }
    .padding()
    .frame(width: 300)
}

#Preview("Linear") {
    let layout = StackTreeLayout(MockData.linearStack)
    return VStack(spacing: 0) {
        ForEach(layout.rows) { row in
            HStack {
                StackLaneGutter(segments: row.segments, lane: row.lane, laneCount: layout.laneCount)
                Text(row.branch).font(.monoCaption)
                Spacer()
            }
            .frame(height: 44)
        }
    }
    .padding()
    .frame(width: 360)
}
