// Views/Sidebar/StacksSidebarSection.swift
// Grove
//
// Stacked branches, one disclosure group per stack with each layer indented under its parent.

import SwiftUI

struct StacksSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel
    @State private var sheets = BranchSheetState()

    var body: some View {
        if !viewModel.stacks.isEmpty {
            Section {
                ForEach(viewModel.stacks) { stack in
                    StackDisclosure(stack: stack) { layer in row(layer, in: stack) }
                }
            } header: {
                SidebarSectionHeader(title: "Stacks", count: viewModel.stacks.count)
            }
            .branchActionSheets($sheets)
        }
    }

    @ViewBuilder
    private func row(_ layer: StackLayer, in stack: BranchStack) -> some View {
        if let branch = viewModel.localBranches.first(where: { $0.name == layer.branch }) {
            StackSidebarRow(layer: layer, branch: branch, worktree: viewModel.worktree(checkingOut: branch))
                .tag(SidebarItem.branch(branch))
                .draggable(branch.name)
                .dropDestination(for: String.self) { items, _ in
                    guard let payload = items.first else { return false }
                    return viewModel.handleDrop(payload, onBranch: branch, option: NSEvent.modifierFlags.contains(.option))
                }
                .contextMenu {
                    BranchContextMenu(
                        branch: branch,
                        isPinned: viewModel.pinnedBranchNames.contains(branch.name),
                        onCreateBranch: { sheets.createFromRef = CreateBranchRequest(ref: branch.name) },
                        onRename: { sheets.branchToRename = branch },
                        onTrack: { sheets.branchToTrack = branch },
                        onDelete: { sheets.branchToDelete = branch }
                    )
                }
        }
    }
}

/// A stack's layers; it opens when it holds the checked-out branch or needs attention.
private struct StackDisclosure<Row: View>: View {
    let stack: BranchStack
    @ViewBuilder let row: (StackLayer) -> Row
    @State private var isExpanded: Bool

    init(stack: BranchStack, @ViewBuilder row: @escaping (StackLayer) -> Row) {
        self.stack = stack
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
        }
        .onChange(of: stack.layers.contains(where: \.isHEAD)) { _, contains in
            if contains { isExpanded = true }
        }
    }
}

#Preview {
    let vm = SidebarViewModel(repository: MockGitRepository())
    vm.refs.replace(localBranches: MockData.stackBranches, stacks: [MockData.linearStack, MockData.splitStack])
    return List(selection: Binding<SidebarItem?>.constant(.history)) {
        StacksSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .frame(width: 280, height: 360)
}
