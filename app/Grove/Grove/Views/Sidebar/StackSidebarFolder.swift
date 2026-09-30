// Views/Sidebar/StackSidebarFolder.swift
// Grove

import SwiftUI

/// A stack in the Branches section, with each layer indented under its parent;
/// it opens when it holds the checked-out branch or needs attention.
struct StackSidebarFolder<Row: View>: View {
    let stack: BranchStack
    let showStack: () -> Void
    @ViewBuilder let row: (StackLayer) -> Row
    @State private var isExpanded: Bool

    init(stack: BranchStack, showStack: @escaping () -> Void, @ViewBuilder row: @escaping (StackLayer) -> Row) {
        self.stack = stack
        self.showStack = showStack
        self.row = row
        _isExpanded = State(initialValue: stack.layers.contains(where: \.isHEAD) || stack.needsAttention)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(stack.layers) { row($0) }
        } label: {
            SidebarRow(title: stack.name, symbol: "square.stack.3d.up",
                       tint: stack.needsAttention ? Theme.warning : Theme.textSecondary) {
                Text("\(stack.layers.count)").font(.system(size: 11, design: .monospaced))
            }
            .help(stack.needsAttention ? "\(stack.name): some layers need a restack or retarget" : "\(stack.name) on \(stack.trunk)")
            .contextMenu {
                Button("Show Stack", systemImage: "square.stack.3d.up", action: showStack)
            }
        }
        .onChange(of: stack.layers.contains(where: \.isHEAD)) { _, contains in
            if contains { isExpanded = true }
        }
    }
}

#Preview {
    List {
        ForEach([MockData.linearStack, MockData.splitStack]) { stack in
            StackSidebarFolder(stack: stack, showStack: {}) { layer in
                StackSidebarRow(layer: layer, branch: MockData.stackBranches.first { $0.name == layer.branch }!)
            }
        }
    }
    .listStyle(.sidebar)
    .frame(width: 280, height: 360)
}
