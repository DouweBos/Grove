// Views/Sidebar/BranchesSidebarSection.swift
// Grove
//
// Local branches: pinned first, then flat names, then stacks, then "prefix/" groups.
// Rows are draggable; dropping a ref on the header starts a new branch from it.

import GroveKit
import SwiftUI

struct BranchesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel

    @State private var sheets = BranchSheetState()

    var body: some View {
        Section {
            if !viewModel.pinnedBranches.isEmpty {
                ForEach(viewModel.pinnedBranches) { branch in
                    branchRow(branch, isPinned: true, showsFullName: true)
                }
            }
            ForEach(viewModel.localBranchGroups, id: \.prefix) { group in
                if let prefix = group.prefix {
                    BranchFolder(prefix: prefix, branches: group.branches) { branch in
                        branchRow(branch, isPinned: viewModel.pinnedBranchNames.contains(branch.name))
                    }
                } else {
                    ForEach(group.branches) { branch in
                        branchRow(branch, isPinned: viewModel.pinnedBranchNames.contains(branch.name))
                    }
                    ForEach(viewModel.stacks) { stack in
                        StackSidebarFolder(stack: stack, showStack: { viewModel.showStack(stack) }) {
                            stackRow($0, lanes: $1)
                        }
                    }
                }
            }
        } header: {
            SidebarSectionHeader(title: "Branches", count: viewModel.localBranches.count - viewModel.archivedBranches.count)
                .dropDestination(for: String.self) { items, _ in
                    guard let ref = items.first, !ref.isEmpty else { return false }
                    sheets.createFromRef = CreateBranchRequest(ref: ref)
                    return true
                }
        }
        .branchActionSheets($sheets)
    }

    private func branchRow(_ branch: BranchInfo, isPinned: Bool, showsFullName: Bool = false) -> some View {
        actions(for: branch, isPinned: isPinned, on: SidebarBranchRow(
            branch: branch, isPinned: isPinned, showsFullName: showsFullName,
            worktree: viewModel.actions.worktree(checkingOut: branch), parent: viewModel.refs.parents[branch.name],
            pullRequest: viewModel.refs.pullRequest(for: branch), ciStatus: viewModel.refs.ciStatus(for: branch)))
    }

    @ViewBuilder
    private func stackRow(_ layer: StackLayer, lanes: StackSidebarLanes) -> some View {
        if let branch = viewModel.localBranches.first(where: { $0.name == layer.branch }) {
            actions(for: branch, isPinned: viewModel.pinnedBranchNames.contains(branch.name), inStack: true,
                    on: StackSidebarRow(layer: layer, lanes: lanes, branch: branch, worktree: viewModel.actions.worktree(checkingOut: branch)))
        }
    }

    /// Selection, drag and drop and the context menu, the same for a plain row and a stack layer.
    private func actions(for branch: BranchInfo, isPinned: Bool, inStack: Bool = false, on row: some View) -> some View {
        row
            .tag(SidebarItem.branch(branch))
            .draggable(branch.name)
            // Another branch dropped here merges into this one (Option rebases this one onto it); a remote branch pulls.
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.first else { return false }
                return viewModel.handleDrop(payload, onBranch: branch, option: NSEvent.modifierFlags.contains(.option))
            }
            .contextMenu {
                if inStack {
                    Button("Show Stack", systemImage: "square.stack.3d.up") { viewModel.showStack(containing: branch.name) }
                    Divider()
                }
                BranchContextMenu(
                    branch: branch,
                    isPinned: isPinned,
                    onCreateBranch: { sheets.createFromRef = CreateBranchRequest(ref: branch.name) },
                    onRename: { sheets.branchToRename = branch },
                    onTrack: { sheets.branchToTrack = branch },
                    onDelete: { sheets.branchToDelete = branch }
                )
            }
    }
}

/// A "prefix/" group of branches; it opens when it holds the checked-out branch, so HEAD is always visible.
private struct BranchFolder<Row: View>: View {
    let prefix: String
    let branches: [BranchInfo]
    @ViewBuilder let row: (BranchInfo) -> Row
    @State private var isExpanded: Bool

    init(prefix: String, branches: [BranchInfo], @ViewBuilder row: @escaping (BranchInfo) -> Row) {
        self.prefix = prefix
        self.branches = branches
        self.row = row
        _isExpanded = State(initialValue: branches.contains(where: \.isHEAD))
    }

    private var containsHEAD: Bool { branches.contains(where: \.isHEAD) }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ForEach(branches) { row($0) }
        } label: {
            SidebarRow(title: prefix, symbol: "folder", tint: Theme.textSecondary) {
                Text("\(branches.count)").font(.system(size: 11, design: .monospaced))
            }
        }
        // A checkout into this folder opens it; it never closes on its own, so manual toggles stick.
        .onChange(of: containsHEAD) { _, contains in
            if contains { isExpanded = true }
        }
    }
}

/// Identifies a "new branch from ref" sheet.
struct CreateBranchRequest: Identifiable {
    let ref: String
    var id: String { ref }
}

// MARK: - BranchContextMenu

/// Actions for a local branch.
struct BranchContextMenu: View {
    @Environment(SidebarViewModel.self) private var viewModel

    let branch: BranchInfo
    let isPinned: Bool
    let onCreateBranch: () -> Void
    let onRename: () -> Void
    let onTrack: () -> Void
    let onDelete: () -> Void

    /// Git refuses to check out, delete or archive a branch another worktree has checked out.
    private var worktree: WorktreeInfo? { viewModel.actions.worktree(checkingOut: branch) }

    var body: some View {
        if let worktree {
            Button("Open Worktree in New Tab", systemImage: "plus.rectangle.on.rectangle") { viewModel.openInNewTab(worktree) }
            Button("Switch to Worktree", systemImage: "tree") { viewModel.switchTo(worktree) }
        } else {
            Button("Check Out \u{201C}\(branch.name)\u{201D}", systemImage: "arrow.uturn.backward") {
                Task { await viewModel.actions.checkout(branch: branch) }
            }
            .disabled(branch.isHEAD)
        }
        Button("New Branch from \u{201C}\(branch.name)\u{201D}…", systemImage: "arrow.triangle.branch", action: onCreateBranch)
        if let gitFlow = viewModel.gitFlow, let flow = gitFlow.config?.classify(branch: branch.name) {
            Button("Finish \(flow.kind.title) \u{201C}\(flow.name)\u{201D}…", systemImage: flow.kind.symbol) {
                gitFlow.present(.finish(flow.kind, name: flow.name))
            }
        }
        if let pullRequest = viewModel.refs.pullRequest(for: branch) {
            BranchPullRequestButton(pullRequest: pullRequest)
        } else {
            Button("Create Pull Request\u{2026}", systemImage: "arrow.triangle.pull") { viewModel.createPullRequest(for: branch) }
        }
        Button("Show Runs for Branch", systemImage: "play.circle") { viewModel.showRuns(for: branch) }
        Button("Reveal in History", systemImage: "clock.arrow.circlepath") { viewModel.revealInHistory(.branch(branch)) }
        ExportFilesButton(ref: branch.name)
        Divider()
        Button("Merge into Current Branch", systemImage: "arrow.triangle.merge") {
            Task { await viewModel.actions.merge(branch: branch) }
        }
        .disabled(branch.isHEAD)
        Button("Rebase Current Branch onto This", systemImage: "arrow.triangle.pull") {
            Task { await viewModel.actions.rebase(onto: branch) }
        }
        .disabled(branch.isHEAD)
        Divider()
        Button("Rename…", systemImage: "pencil", action: onRename)
        Button(branch.upstream == nil ? "Track Remote Branch\u{2026}" : "Change Tracked Branch\u{2026}",
               systemImage: "arrow.left.arrow.right", action: onTrack)
            .disabled(viewModel.actions.trackableRemoteBranches.isEmpty)
        if let upstream = branch.upstreamShortName {
            Button("Stop Tracking \u{201C}\(upstream)\u{201D}", systemImage: "xmark.circle") {
                Task { await viewModel.actions.stopTracking(branch) }
            }
        }
        Button(isPinned ? "Unpin" : "Pin to Top", systemImage: isPinned ? "pin.slash" : "pin") {
            viewModel.togglePin(branch: branch)
        }
        Button("Archive", systemImage: "archivebox") { viewModel.archive(branch: branch) }
            .disabled(branch.isHEAD || worktree != nil)
        Button("Copy Name", systemImage: "doc.on.doc") {
            GroveClipboard.copy(branch.name)
        }
        Divider()
        // The dialog offers to remove the worktree first.
        Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
            .disabled(branch.isHEAD)
    }
}

#Preview {
    let vm = SidebarViewModel(repository: MockGitRepository())
    vm.refs.replace(localBranches: MockData.branches.filter(\.isLocal) + MockData.stackBranches,
                    stacks: [MockData.linearStack, MockData.splitStack])
    return List(selection: Binding<SidebarItem?>.constant(.history)) {
        BranchesSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .frame(width: 280, height: 480)
}
