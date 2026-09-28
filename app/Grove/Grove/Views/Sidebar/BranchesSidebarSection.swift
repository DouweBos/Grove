// Views/Sidebar/BranchesSidebarSection.swift
// Grove
//
// Local branches: pinned first, then flat names, then "prefix/" groups.
// Rows are draggable; dropping a ref on the header starts a new branch from it.

import SwiftUI

struct BranchesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel

    @State private var createFromRef: CreateBranchRequest?
    @State private var branchToRename: BranchInfo?
    @State private var branchToDelete: BranchInfo?

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
                }
            }
        } header: {
            SidebarSectionHeader(title: "Branches", count: viewModel.localBranches.count - viewModel.archivedBranches.count)
                .dropDestination(for: String.self) { items, _ in
                    guard let ref = items.first, !ref.isEmpty else { return false }
                    createFromRef = CreateBranchRequest(ref: ref)
                    return true
                }
        }
        .sheet(item: $createFromRef) { request in
            CreateBranchDialogView(
                repository: viewModel.repository,
                localBranches: viewModel.localBranches,
                fromRef: request.ref
            ) { _ in
                Task { await viewModel.didChangeRepository() }
            }
        }
        .sheet(item: $branchToRename) { branch in
            RenameBranchDialogView(repository: viewModel.repository, branch: branch) {
                Task { await viewModel.didChangeRepository() }
            }
        }
        .sheet(item: $branchToDelete) { branch in
            DeleteBranchDialogView(repository: viewModel.repository, branch: branch,
                                   onDeleted: { viewModel.recordBranchDeletion(branch) },
                                   onComplete: { Task { await viewModel.didChangeRepository() } })
        }
    }

    private func branchRow(_ branch: BranchInfo, isPinned: Bool, showsFullName: Bool = false) -> some View {
        SidebarBranchRow(branch: branch, isPinned: isPinned, showsFullName: showsFullName,
                         worktree: viewModel.worktree(checkingOut: branch), parent: viewModel.refs.parents[branch.name],
                         pullRequest: viewModel.refs.openPullRequest(for: branch))
            .tag(SidebarItem.branch(branch))
            .draggable(branch.name)
            .contextMenu {
                BranchContextMenu(
                    branch: branch,
                    isPinned: isPinned,
                    onCreateBranch: { createFromRef = CreateBranchRequest(ref: branch.name) },
                    onRename: { branchToRename = branch },
                    onDelete: { branchToDelete = branch }
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
    let onDelete: () -> Void

    /// Git refuses to check out, delete or archive a branch another worktree has checked out.
    private var worktree: WorktreeInfo? { viewModel.worktree(checkingOut: branch) }

    var body: some View {
        if let worktree {
            Button("Switch to Worktree", systemImage: "tree") { viewModel.switchTo(worktree) }
        } else {
            Button("Check Out \u{201C}\(branch.name)\u{201D}", systemImage: "arrow.uturn.backward") {
                Task { await viewModel.checkout(branch: branch) }
            }
            .disabled(branch.isHEAD)
        }
        Button("New Branch from \u{201C}\(branch.name)\u{201D}…", systemImage: "arrow.triangle.branch", action: onCreateBranch)
        if let pullRequest = viewModel.refs.openPullRequest(for: branch) {
            OpenPullRequestButton(pullRequest: pullRequest)
        }
        Divider()
        Button("Merge into Current Branch", systemImage: "arrow.triangle.merge") {
            Task { await viewModel.merge(branch: branch) }
        }
        .disabled(branch.isHEAD)
        Button("Rebase Current Branch onto This", systemImage: "arrow.triangle.pull") {
            Task { await viewModel.rebase(onto: branch) }
        }
        .disabled(branch.isHEAD)
        Divider()
        Button("Rename…", systemImage: "pencil", action: onRename)
        Button(isPinned ? "Unpin" : "Pin to Top", systemImage: isPinned ? "pin.slash" : "pin") {
            viewModel.togglePin(branch: branch)
        }
        Button("Archive", systemImage: "archivebox") { viewModel.archive(branch: branch) }
            .disabled(branch.isHEAD || worktree != nil)
        Button("Copy Name", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(branch.name, forType: .string)
        }
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive, action: onDelete)
            .disabled(branch.isHEAD || worktree != nil)
    }
}

#Preview {
    let vm = SidebarViewModel(repository: MockGitRepository())
    vm.refs.replace(localBranches: MockData.branches.filter(\.isLocal))
    return List(selection: Binding<SidebarItem?>.constant(.history)) {
        BranchesSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .frame(width: 240, height: 300)
}
