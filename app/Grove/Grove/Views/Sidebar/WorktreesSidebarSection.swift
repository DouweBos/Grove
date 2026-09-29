// Views/Sidebar/WorktreesSidebarSection.swift
// Grove

import AppKit
import SwiftUI

/// The repository's other worktrees; from a linked worktree that includes the main one.
/// Double-click opens it in a new tab; Switch to Worktree runs this window's git there instead.
struct WorktreesSidebarSection: View {

    @Environment(SidebarViewModel.self) private var viewModel
    @State private var isExpanded = true

    var body: some View {
        let worktrees = viewModel.otherWorktrees
        if !worktrees.isEmpty {
            Section(isExpanded: $isExpanded) {
                ForEach(worktrees) { row($0) }
            } header: {
                SidebarSectionHeader(title: "Worktrees", count: worktrees.count)
            }
        }
    }

    private func row(_ worktree: WorktreeInfo) -> some View {
        SidebarRow(
            title: worktree.branch ?? "Detached HEAD",
            symbol: worktree.isPrunable ? "questionmark.folder" : "tree",
            tint: worktree.isPrunable ? Theme.warning : Theme.info,
            detail: worktree.branch.flatMap { viewModel.refs.branchPullRequests[$0].flatMap { $0.isMerged ? nil : $0.label } }
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
        .onTapGesture(count: 2) { viewModel.openInNewTab(worktree) }
        .help(worktree.isPrunable
              ? "\(abbreviatingHome(worktree.path)) no longer exists"
              : "\(abbreviatingHome(worktree.path)) · \(worktree.shortSHA)\nDouble-click to open in a new tab")
        .contextMenu {
            Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") { viewModel.openInNewTab(worktree) }
                .disabled(worktree.isPrunable)
            Button("Switch to Worktree", systemImage: "tree") { viewModel.switchTo(worktree) }
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
                    Button("Remove Worktree…", systemImage: "trash", role: .destructive) { viewModel.requestRemoval(of: worktree) }
                        .disabled(worktree.isLocked)
                }
            }
        }
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
