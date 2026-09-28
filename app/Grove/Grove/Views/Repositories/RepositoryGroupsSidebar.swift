// Views/Repositories/RepositoryGroupsSidebar.swift
// Grove
//
// Browser sidebar: ungrouped repositories, then collapsible groups.
// Bookmarks move between groups via the context menu or drag and drop.

import AppKit
import SwiftUI

struct RepositoryGroupsSidebar: View {
    @Environment(WindowViewModel.self) private var viewModel

    @State private var groupPendingDelete: BookmarkGroupData?

    var body: some View {
        List(selection: Binding(get: { viewModel.selectedBookmarkID }, set: { viewModel.selectBookmark($0) })) {
            let ungrouped = viewModel.ungroupedBookmarks
            if !ungrouped.isEmpty {
                Section {
                    RepositoryBookmarksList(bookmarks: ungrouped)
                } header: {
                    SectionLabel(title: "Repositories", count: ungrouped.count)
                }
                .dropDestination(for: RepositoryBookmarkData.self) { items, _ in
                    items.forEach { viewModel.moveBookmark($0, toGroup: nil) }
                    return !items.isEmpty
                }
            }

            let groups = viewModel.visibleGroups
            if !groups.isEmpty {
                Section {
                    ForEach(groups) { group in
                        RepositoryGroupSection(group: group) { groupPendingDelete = group }
                    }
                } header: {
                    SectionLabel(title: "Groups")
                }
            }

            if viewModel.isSearching && ungrouped.isEmpty && groups.isEmpty {
                Text("No repositories match.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .selectionDisabled()
            }
        }
        .listStyle(.sidebar)
        .searchable(
            text: Binding(get: { viewModel.searchText }, set: { viewModel.setSearchText($0) }),
            placement: .sidebar,
            prompt: "Filter Repositories"
        )
        .dragContainer(for: RepositoryBookmarkData.self) { draggedIDs in
            draggedIDs.compactMap { id in viewModel.manager.bookmarks.first { $0.id == id } }
        }
        .contextMenu(forSelectionType: UUID.self) { selectedIDs in
            if let id = selectedIDs.first, let row = viewModel.row(withID: id) {
                if viewModel.isSyntheticWorktreeRow(row) {
                    WorktreeActions(row: row)
                } else {
                    BookmarkActions(bookmark: row)
                }
            } else {
                Button("New Group…", systemImage: "folder.badge.plus") { viewModel.showNewGroupDialog() }
            }
        } primaryAction: { selectedIDs in
            guard let id = selectedIDs.first, let row = viewModel.row(withID: id) else { return }
            viewModel.openBookmark(row)
        }
        // Worktrees come and go outside Grove, so re-read them whenever the list or app focus changes.
        .onChange(of: viewModel.manager.bookmarks.map(\.path)) { viewModel.refreshWorktrees() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            viewModel.refreshWorktrees()
        }
        .confirmationDialog(
            "Delete the group \u{201C}\(groupPendingDelete?.name ?? "")\u{201D}?",
            isPresented: Binding(get: { groupPendingDelete != nil }, set: { if !$0 { groupPendingDelete = nil } }),
            presenting: groupPendingDelete
        ) { group in
            Button("Delete Group", role: .destructive) { viewModel.deleteGroup(group) }
        } message: { _ in
            Text("Its repositories move to the ungrouped list. Nothing is deleted from disk.")
        }
        .alert(
            "Delete Repository",
            isPresented: Binding(get: { viewModel.bookmarkPendingDelete != nil }, set: { if !$0 { viewModel.cancelDelete() } }),
            presenting: viewModel.bookmarkPendingDelete
        ) { _ in
            Button("Keep Files") { viewModel.confirmDelete(movingToTrash: false) }
                .keyboardShortcut(.defaultAction)
            Button("Move to Trash", role: .destructive) { viewModel.confirmDelete(movingToTrash: true) }
            Button("Cancel", role: .cancel) { viewModel.cancelDelete() }
        } message: { bookmark in
            Text("\u{201C}\(bookmark.displayName)\u{201D} is removed from Grove. Keep its folder on disk, "
                 + "or move it to the Trash along with any uncommitted work in it?")
        }
    }
}

// MARK: - BookmarkActions

private struct BookmarkActions: View {
    @Environment(WindowViewModel.self) private var viewModel
    let bookmark: RepositoryBookmarkData

    var body: some View {
        Button("Open", systemImage: "arrow.up.forward.app") { viewModel.openBookmark(bookmark) }
        OpenInNewWindowButton(path: bookmark.path)
        FolderActions(path: bookmark.path)
        Divider()
        Button("Rename\u{2026}", systemImage: "pencil") { viewModel.showRenameBookmarkDialog(bookmark) }
        Menu("Move to Group", systemImage: "tray.and.arrow.down") {
            ForEach(viewModel.sortedGroups) { group in
                Button(group.name) { viewModel.moveBookmark(bookmark, toGroup: group.id) }
                    .disabled(bookmark.groupID == group.id)
            }
            if bookmark.groupID != nil {
                Divider()
                Button("Remove from Group") { viewModel.moveBookmark(bookmark, toGroup: nil) }
            }
            Divider()
            Button("New Group…") { viewModel.showNewGroupDialog() }
        }
        Button("Sort \(groupName) by Name", systemImage: "arrow.up.arrow.down") {
            viewModel.sortBookmarksByName(inGroup: bookmark.groupID)
        }
        Divider()
        Button("Delete\u{2026}", systemImage: "trash", role: .destructive) { viewModel.requestDelete(bookmark) }
    }

    private var groupName: String {
        viewModel.sortedGroups.first { $0.id == bookmark.groupID }?.name ?? "Repositories"
    }
}

private struct OpenInNewWindowButton: View {
    let path: String
    @Environment(\.openWindow) private var openWindow
    @Environment(WindowStore.self) private var windows

    var body: some View {
        Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") {
            windows.requestTab()
            openWindow(id: GroveApp.mainWindowID, value: RepositoryReference(path: path))
        }
        Button("Open in New Window", systemImage: "macwindow.badge.plus") {
            openWindow(id: GroveApp.mainWindowID, value: RepositoryReference(path: path))
        }
    }
}

/// Opening the folder elsewhere; shared by bookmarks and nested worktrees.
private struct FolderActions: View {
    let path: String

    var body: some View {
        Button("Open in Terminal", systemImage: "terminal") {
            try? ExternalToolLauncher.openInTerminal(URL(fileURLWithPath: path))
        }
        Button("Reveal in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
        Button("Copy Path", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(path, forType: .string)
        }
    }
}

// MARK: - WorktreeActions

/// Menu for a worktree listed only because its main repository is bookmarked.
private struct WorktreeActions: View {
    let row: RepositoryBookmarkData
    @Environment(WindowViewModel.self) private var viewModel

    var body: some View {
        Button("Open", systemImage: "arrow.up.forward.app") { viewModel.openBookmark(row) }
        OpenInNewWindowButton(path: row.path)
        FolderActions(path: row.path)
    }
}

// MARK: - RepositoryGroupSection

private struct RepositoryGroupSection: View {

    @Environment(WindowViewModel.self) private var viewModel
    let group: BookmarkGroupData
    let onDelete: () -> Void
    @State private var isExpanded = true

    var body: some View {
        let bookmarks = viewModel.bookmarks(for: group.id)
        DisclosureGroup(isExpanded: Binding(
            get: { isExpanded || viewModel.isSearching },
            set: { isExpanded = $0 }
        )) {
            RepositoryBookmarksList(bookmarks: bookmarks)
        } label: {
            RepositoryGroupRow(group: group, count: bookmarks.count)
                .dropDestination(for: RepositoryBookmarkData.self) { items, _ in
                    items.forEach { viewModel.moveBookmark($0, toGroup: group.id) }
                    return !items.isEmpty
                }
                .contextMenu {
                    Button("Rename…", systemImage: "pencil") { viewModel.showRenameGroupDialog(group) }
                    Button("New Group…", systemImage: "folder.badge.plus") { viewModel.showNewGroupDialog() }
                    Divider()
                    Button("Sort Repositories by Name", systemImage: "arrow.up.arrow.down") {
                        viewModel.sortBookmarksByName(inGroup: group.id)
                    }
                    Button("Sort Groups by Name", systemImage: "arrow.up.arrow.down") { viewModel.sortGroupsByName() }
                    Divider()
                    Button("Delete Group…", systemImage: "trash", role: .destructive, action: onDelete)
                }
        }
    }
}

// MARK: - RepositoryBookmarksList

private struct RepositoryBookmarksList: View {
    let bookmarks: [RepositoryBookmarkData]

    var body: some View {
        ForEach(bookmarks) { bookmark in
            RepositoryEntry(bookmark: bookmark)
        }
    }
}

/// A repository row, with its linked worktrees nested underneath when it has any.
private struct RepositoryEntry: View {
    @Environment(WindowViewModel.self) private var viewModel
    let bookmark: RepositoryBookmarkData
    @State private var isExpanded = false

    var body: some View {
        let worktrees = viewModel.worktreeRows(of: bookmark)
        if worktrees.isEmpty {
            row
        } else {
            DisclosureGroup(isExpanded: Binding(
                get: { isExpanded || viewModel.isSearching || worktrees.contains { $0.id == viewModel.selectedBookmarkID } },
                set: { isExpanded = $0 }
            )) {
                ForEach(worktrees) { worktree in
                    RepositoryRow(bookmark: worktree, worktree: viewModel.linkedWorktree(for: worktree))
                        .tag(worktree.id)
                }
            } label: {
                row
            }
        }
    }

    private var row: some View {
        RepositoryRow(
            bookmark: bookmark,
            worktree: viewModel.linkedWorktree(for: bookmark),
            worktreeCount: viewModel.worktreeIndex.worktreesByRepository[bookmark.path]?.count ?? 0
        )
        .tag(bookmark.id)
        .draggable(bookmark)
    }
}

#Preview {
    NavigationSplitView {
        RepositoryGroupsSidebar()
    } detail: {
        Theme.background
    }
    .environment(WindowViewModel(manager: MockRepositoryManager()))
    .frame(width: 700, height: 500)
}
