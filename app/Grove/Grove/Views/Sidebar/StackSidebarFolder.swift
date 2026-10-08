// Views/Sidebar/StackSidebarFolder.swift
// Grove

import GroveKit
import SwiftUI

/// A stack in the Branches section drawn as a lane graph, first layer on top; selecting it opens the Stack tab.
/// It's open while it holds the checked-out branch, as a branch folder is.
struct StackSidebarFolder<Row: View>: View {
    let stack: BranchStack
    let showStack: () -> Void
    @ViewBuilder let row: (StackLayer, StackSidebarLanes) -> Row
    @State private var expansion: FolderExpansion

    init(stack: BranchStack, showStack: @escaping () -> Void, @ViewBuilder row: @escaping (StackLayer, StackSidebarLanes) -> Row) {
        self.stack = stack
        self.showStack = showStack
        self.row = row
        _expansion = State(initialValue: FolderExpansion(containsHEAD: stack.layers.contains(where: \.isHEAD)))
    }

    var body: some View {
        DisclosureGroup(isExpanded: Binding(get: { expansion.isExpanded }, set: { expansion.toggle(to: $0) })) {
            ForEach(StackSidebarLanes.rows(of: stack), id: \.layer.branch) { row($0.layer, $0.lanes) }
        } label: {
            SidebarRow(title: stack.name, symbol: "square.stack.3d.up",
                       tint: stack.needsAttention ? Theme.warning : Theme.textSecondary) {
                Text("\(stack.layers.count)").font(.system(size: 11, design: .monospaced))
            }
            .tag(SidebarItem.branchStack(stack.id))
            .help(stack.needsAttention ? "\(stack.name): some layers need a restack or retarget" : "\(stack.name) on \(stack.trunk)")
            .contextMenu {
                Button("Show Stack", systemImage: "square.stack.3d.up", action: showStack)
            }
        }
        .onChange(of: stack.layers.contains(where: \.isHEAD)) { _, contains in expansion.headChanged(contains: contains) }
    }
}

#Preview {
    List {
        ForEach([MockData.linearStack, MockData.splitStack]) { stack in
            StackSidebarFolder(stack: stack, showStack: {}) { layer, lanes in
                StackSidebarRow(layer: layer, lanes: lanes, branch: MockData.stackBranches.first { $0.name == layer.branch }!)
            }
        }
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 360)
}

/// One sidebar row's slice of the stack's lane graph.
struct StackSidebarLanes: Equatable {
    var segments: [StackTreeLayout.Segment] = []
    var lane = 0
    var laneCount = 1

    /// The Stack tab's graph upside down, so rows read in stack order; the gutter is flipped to match.
    /// The root's lines stop at its node since no trunk row follows in the sidebar.
    static func rows(of stack: BranchStack) -> [(layer: StackLayer, lanes: StackSidebarLanes)] {
        let layout = StackTreeLayout(stack)
        return layout.rows.enumerated().reversed().compactMap { index, row in
            guard let layer = stack.layer(row.branch) else { return nil }
            var segments = row.segments
            if index == layout.rows.count - 1 {
                segments = segments.compactMap { segment in
                    switch segment {
                    case .bottom: nil
                    case .through(let lane): .top(lane)
                    default: segment
                    }
                }
            }
            return (layer, StackSidebarLanes(segments: segments, lane: row.lane, laneCount: layout.laneCount))
        }
    }
}
