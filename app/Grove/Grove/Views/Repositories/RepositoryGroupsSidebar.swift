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
            if let id = selectedIDs.first,
               let bookmark = viewModel.manager.bookmarks.first(where: { $0.id == id }) {
                BookmarkActions(bookmark: bookmark)
            } else {
                Button("New Group…", systemImage: "folder.badge.plus") { viewModel.showNewGroupDialog() }
            }
        } primaryAction: { selectedIDs in
            guard let id = selectedIDs.first,
                  let bookmark = viewModel.manager.bookmarks.first(where: { $0.id == id }) else { return }
            viewModel.openBookmark(bookmark)
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
    }
}

// MARK: - BookmarkActions

private struct BookmarkActions: View {
    @Environment(WindowViewModel.self) private var viewModel
    let bookmark: RepositoryBookmarkData

    var body: some View {
        Button("Open", systemImage: "arrow.up.forward.app") { viewModel.openBookmark(bookmark) }
        Button("Reveal in Finder", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bookmark.path)])
        }
        Button("Copy Path", systemImage: "doc.on.doc") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(bookmark.path, forType: .string)
        }
        Divider()
        Menu("Move to Group") {
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
        Divider()
        Button("Remove from List", systemImage: "minus.circle", role: .destructive) {
            viewModel.removeBookmark(bookmark)
        }
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
            RepositoryRow(bookmark: bookmark)
                .tag(bookmark.id)
                .draggable(bookmark)
        }
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
