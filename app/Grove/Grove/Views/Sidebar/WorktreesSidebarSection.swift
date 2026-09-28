// Views/Sidebar/WorktreesSidebarSection.swift
// Grove

import AppKit
import SwiftUI

/// The repository's other worktrees; from a linked worktree that includes the main one.
/// Double-click switches this window to it, so git commands run there.
struct WorktreesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel
    @State private var isExpanded = true
    @State private var worktreeToRemove: WorktreeInfo?

    var body: some View {
        let worktrees = viewModel.otherWorktrees
        if !worktrees.isEmpty {
            Section(isExpanded: $isExpanded) {
                ForEach(worktrees) { row($0) }
            } header: {
                SidebarSectionHeader(title: "Worktrees", count: worktrees.count)
            }
            .confirmationDialog(
                "Remove the worktree \u{201C}\(worktreeToRemove?.branch ?? worktreeToRemove?.folderName ?? "")\u{201D}?",
                isPresented: Binding(get: { worktreeToRemove != nil }, set: { if !$0 { worktreeToRemove = nil } }),
                presenting: worktreeToRemove
            ) { worktree in
                Button("Remove Worktree", role: .destructive) {
                    Task { await viewModel.removeWorktree(path: worktree.path) }
                }
            } message: { worktree in
                Text("Deletes the folder \(abbreviatingHome(worktree.path)). Its branch is kept.")
            }
        }
    }

    private func row(_ worktree: WorktreeInfo) -> some View {
        SidebarRow(
            title: worktree.branch ?? "Detached HEAD",
            symbol: worktree.isPrunable ? "questionmark.folder" : "tree",
            tint: worktree.isPrunable ? Theme.warning : Theme.info,
            detail: worktree.branch.flatMap { viewModel.refs.openPullRequests[$0]?.label }
        ) {
            if worktree.isMain {
                Text("main").font(.system(size: 11, weight: .medium))
            } else if worktree.isPrunable {
                Text("missing").font(.system(size: 11, weight: .medium))
            } else if worktree.isLocked {
                Image(systemName: "lock.fill").font(.system(size: 10)).accessibilityLabel("Locked")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open(worktree) }
        .help(worktree.isPrunable
              ? "\(abbreviatingHome(worktree.path)) no longer exists"
              : "\(abbreviatingHome(worktree.path)) · \(worktree.shortSHA)\nDouble-click to switch to this worktree")
        .contextMenu {
            Button("Switch to Worktree", systemImage: "tree") { open(worktree) }
                .disabled(worktree.isPrunable)
            Button("Reveal in Finder", systemImage: "folder") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: worktree.path)])
            }
            .disabled(worktree.isPrunable)
            Button("Copy Path", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(worktree.path, forType: .string)
            }
            if !worktree.isMain {
                Divider()
                if worktree.isPrunable {
                    Button("Prune Missing Worktrees", systemImage: "scissors") {
                        Task { await viewModel.pruneWorktrees() }
                    }
                } else {
                    Button("Remove Worktree…", systemImage: "trash", role: .destructive) { worktreeToRemove = worktree }
                        .disabled(worktree.isLocked)
                }
            }
        }
    }

    private func open(_ worktree: WorktreeInfo) {
        viewModel.switchTo(worktree)
    }
}

#Preview {
    let vm = SidebarViewModel(repository: MockGitRepository())
    return List {
        WorktreesSidebarSection()
    }
    .listStyle(.sidebar)
    .environment(vm)
    .environment(WindowViewModel(manager: MockRepositoryManager()))
    .task { await vm.refresh() }
    .frame(width: 240, height: 140)
}
