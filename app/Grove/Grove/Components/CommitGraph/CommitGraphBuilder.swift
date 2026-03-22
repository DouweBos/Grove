// Components/CommitGraph/CommitGraphBuilder.swift
// Grove
//
// Builds a lane-based commit graph from a topologically ordered commit list.
// The resulting GraphNode values carry enough information for CommitGraphColumn
// to draw vertical lines, merge edges, and commit circles without any further
// knowledge of the commit topology.

import SwiftUI

// MARK: - GraphNode

/// All drawing information for a single commit row in the graph column.
struct GraphNode: Identifiable {
    /// The commit SHA — stable cross-pass identifier.
    let id: String
    /// Zero-based index of the lane this commit sits in (left = 0).
    let column: Int
    /// Primary color for this commit's circle and its downward line.
    let color: Color
    /// All line segments that must be drawn for this row.
    ///
    /// Includes pass-through lanes, the commit's own downward connection,
    /// and any merge edges that converge into this row.
    let edges: [GraphEdge]
    /// True when the commit has more than one parent (merge commit).
    let isMerge: Bool
}

// MARK: - GraphEdge

/// A directed line segment drawn inside a single commit row.
///
/// All coordinates are in *lane units* (multiply by `laneWidth` to get points).
/// `fromColumn` is where the line starts at the **top** of the row;
/// `toColumn` is where it ends at the **bottom** (it may be the same for a
/// straight vertical pass-through, or different for a diagonal merge edge).
struct GraphEdge {
    /// Lane column at the top of this row.
    let fromColumn: Int
    /// Lane column at the bottom of this row.
    let toColumn: Int
    /// The color to use when stroking this edge.
    let color: Color
}

// MARK: - Lane Color Palette

/// Eight perceptually distinct colors assigned to lanes by modulo index.
private let laneColorPalette: [Color] = [
    Color(red: 0.20, green: 0.60, blue: 1.00), // blue
    Color(red: 0.18, green: 0.75, blue: 0.45), // green
    Color(red: 1.00, green: 0.55, blue: 0.10), // orange
    Color(red: 0.65, green: 0.30, blue: 0.90), // purple
    Color(red: 0.95, green: 0.35, blue: 0.55), // pink
    Color(red: 0.10, green: 0.78, blue: 0.85), // cyan
    Color(red: 0.90, green: 0.25, blue: 0.25), // red
    Color(red: 0.90, green: 0.75, blue: 0.10) // yellow
]

private func laneColor(for column: Int) -> Color {
    laneColorPalette[column % laneColorPalette.count]
}

// MARK: - CommitGraphBuilder

/// Constructs ``GraphNode`` values for an ordered list of commits.
///
/// ### Algorithm overview
///
/// The builder maintains an array of *active lanes*. Each lane slot either holds
/// the SHA of the next commit it expects (the lane is "live") or is `nil`
/// (the lane is free and can be reused).
///
/// For every commit, in newest-first order:
///
/// 1. **Find the commit's lane.** Scan the active-lane array for a slot whose
///    expected-SHA matches the current commit's SHA. If none matches, the
///    commit starts a new lane (appended at the end, or placed in the first
///    free slot).
///
/// 2. **Assign parent continuations.** The first parent continues the current
///    lane (the slot's expected-SHA is updated to the first parent). Each
///    additional parent (merge parents) is placed in the first free lane or
///    a brand-new lane and gets a merge edge drawn from the current lane to
///    theirs.
///
/// 3. **Collect pass-through edges.** Every other live lane that is neither
///    the commit's own lane nor already claimed by a merge parent gets a
///    straight vertical pass-through edge.
///
/// 4. **Release the lane** when the commit has no parents (root commit).
///
/// This produces correct topology for: linear history, branching, merging,
/// and octopus merges (3+ parents).
@MainActor
final class CommitGraphBuilder {

    // MARK: - Public Interface

    /// Build ``GraphNode`` values for a topologically ordered commit list.
    ///
    /// - Parameter commits: Commits in reverse-chronological / topological
    ///   order (newest first), as returned by `git log --topo-order`.
    /// - Returns: One ``GraphNode`` per commit, in the same order as the input.
    func buildGraph(from commits: [CommitInfo]) -> [GraphNode] {
        // activeLanes[i] = SHA the lane expects next, or nil if free.
        var activeLanes: [String?] = []
        var nodes: [GraphNode] = []
        nodes.reserveCapacity(commits.count)

        for commit in commits {
            let sha = commit.id
            let parents = commit.parentIDs

            // ------------------------------------------------------------------
            // Step 1: Find or allocate the commit's own lane.
            // ------------------------------------------------------------------

            var commitColumn = activeLanes.firstIndex(where: { $0 == sha })

            if commitColumn == nil {
                // This SHA is not expected by any existing lane. This can happen
                // when a branch tip is encountered (no child was processed yet).
                // Place it in the first free slot, or extend the array.
                if let freeSlot = activeLanes.firstIndex(of: nil) {
                    activeLanes[freeSlot] = sha
                    commitColumn = freeSlot
                } else {
                    activeLanes.append(sha)
                    commitColumn = activeLanes.count - 1
                }
            }

            let myColumn = commitColumn! // safe — assigned above

            // ------------------------------------------------------------------
            // Step 2: Determine parent lane assignments.
            //
            // parentAssignments maps parentSHA -> the column it will occupy going
            // forward (i.e. after this row). The first parent continues myColumn;
            // each additional parent gets its own lane.
            // ------------------------------------------------------------------

            // parentColumnMap: parentSHA -> column index it will use below this row.
            var parentColumnMap: [String: Int] = [:]

            if let firstParent = parents.first {
                // First parent continues this lane.
                parentColumnMap[firstParent] = myColumn
            }

            for additionalParent in parents.dropFirst() {
                // Check whether this parent is already tracked in a live lane.
                if let existingLane = activeLanes.firstIndex(where: { $0 == additionalParent }) {
                    parentColumnMap[additionalParent] = existingLane
                } else {
                    // Allocate a new lane for this merge parent.
                    if let freeSlot = activeLanes.firstIndex(of: nil) {
                        activeLanes[freeSlot] = additionalParent
                        parentColumnMap[additionalParent] = freeSlot
                    } else {
                        activeLanes.append(additionalParent)
                        parentColumnMap[additionalParent] = activeLanes.count - 1
                    }
                }
            }

            // ------------------------------------------------------------------
            // Step 3: Collect edges for this row.
            // ------------------------------------------------------------------

            var edges: [GraphEdge] = []

            // Collect the set of columns that will receive a merge edge from
            // myColumn. These must NOT also get a straight pass-through edge —
            // that would double-draw the line.
            let mergeTargetColumns = Set(parents.dropFirst().compactMap { parentColumnMap[$0] })

            // Pass-through edges: every live lane that is not this commit's own
            // lane and not the target of a merge edge below.
            for (col, expected) in activeLanes.enumerated() {
                guard let _ = expected else { continue }
                guard col != myColumn else { continue }
                guard !mergeTargetColumns.contains(col) else { continue }

                edges.append(GraphEdge(
                    fromColumn: col,
                    toColumn: col,
                    color: laneColor(for: col)
                ))
            }

            // Merge edges: from myColumn to each non-first parent's column.
            for additionalParent in parents.dropFirst() {
                let targetCol = parentColumnMap[additionalParent]!
                // The edge is colored using the target lane's color so the
                // incoming branch line visually "arrives" at its lane.
                edges.append(GraphEdge(
                    fromColumn: myColumn,
                    toColumn: targetCol,
                    color: laneColor(for: targetCol)
                ))
            }

            // The commit's own downward line (first-parent continuation or
            // termination). We always draw at least the circle, and if there
            // is a first parent we draw the line going down from myColumn.
            // We represent this as an edge from myColumn to myColumn in the
            // commit's own color — the renderer draws it from the circle
            // downward.
            if parents.first != nil {
                edges.append(GraphEdge(
                    fromColumn: myColumn,
                    toColumn: myColumn,
                    color: laneColor(for: myColumn)
                ))
            }

            // ------------------------------------------------------------------
            // Step 4: Build the GraphNode.
            // ------------------------------------------------------------------

            let node = GraphNode(
                id: sha,
                column: myColumn,
                color: laneColor(for: myColumn),
                edges: edges,
                isMerge: commit.isMerge
            )
            nodes.append(node)

            // ------------------------------------------------------------------
            // Step 5: Update activeLanes for the next iteration.
            // ------------------------------------------------------------------

            if let firstParent = parents.first {
                activeLanes[myColumn] = firstParent
            } else {
                // Root commit — release the lane.
                activeLanes[myColumn] = nil
            }

            // Update lanes for additional parents (already allocated above).
            for (parentSHA, col) in parentColumnMap where parentSHA != (parents.first ?? "") {
                activeLanes[col] = parentSHA
            }

            // Trim trailing nil slots to keep the lane array compact.
            while activeLanes.last == nil {
                activeLanes.removeLast()
            }
        }

        return nodes
    }
}
