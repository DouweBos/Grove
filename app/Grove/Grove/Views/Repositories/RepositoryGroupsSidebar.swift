// Views/Repositories/RepositoryGroupsSidebar.swift
// Grove
//
// Left sidebar of the repository browser showing collapsible groups
// with repository rows underneath each group.
//
// Bookmark moves between groups are supported two ways:
// 1. Context menu → "Move to" submenu (always available)
// 2. macOS 26 `dragContainer` drag-and-drop (keeps List selection working)

import SwiftUI

// MARK: - RepositoryGroupsSidebar

/// Sidebar listing all bookmark groups with their repositories.
///
/// Groups are collapsible rows with an
/// orange folder icon; repos appear indented underneath.
///
/// Bookmark moves across groups use a context-menu "Move to" submenu
/// and macOS 26 `dragContainer`-based drag-and-drop onto group headers.
struct RepositoryGroupsSidebar: View {
    @Environment(WindowViewModel.self) private var viewModel

    var body: some View {
        @Bindable var vm = viewModel
        let sortedGroups = viewModel.manager.bookmarkGroups.sorted(by: { $0.sortOrder < $1.sortOrder })

        List(selection: $vm.selectedBookmarkID) {
            Section("Repositories") {
                RepositoryBookmarksList(bookmarks: viewModel.ungroupedBookmarks)
                    .dropDestination(for: RepositoryBookmarkData.self) { items, _ in
                        for bookmark in items {
                            viewModel.moveBookmark(bookmark, toGroup: nil)
                        }
                        return !items.isEmpty
                    }

                // Grouped bookmarks
                ForEach(sortedGroups) { group in
                    RepositoryGroupSection(group: group)
                }
            }
        }
        .listStyle(.sidebar)
        .dragContainer(for: RepositoryBookmarkData.self) { draggedIDs in
            draggedIDs.compactMap { id in
                viewModel.manager.bookmarks.first { $0.id == id }
            }
        }
        .contextMenu(forSelectionType: UUID.self) { selectedIDs in
            if let id = selectedIDs.first,
               let bookmark = viewModel.manager.bookmarks.first(where: { $0.id == id }) {
                Button("Open") {
                    viewModel.openBookmark(bookmark)
                }
                Divider()
                if !sortedGroups.isEmpty {
                    Menu("Move to") {
                        ForEach(sortedGroups) { group in
                            Button(group.name) {
                                viewModel.moveBookmark(bookmark, toGroup: group.id)
                            }
                            .disabled(bookmark.groupID == group.id)
                        }
                        if bookmark.groupID != nil {
                            Divider()
                            Button("Remove from Group") {
                                viewModel.moveBookmark(bookmark, toGroup: nil)
                            }
                        }
                    }
                }
                Divider()
                Button("Remove from List", role: .destructive) {
                    viewModel.removeBookmark(bookmark)
                }
            }
        } primaryAction: { selectedIDs in
            guard let id = selectedIDs.first,
                  let bookmark = viewModel.manager.bookmarks.first(where: { $0.id == id })
            else { return }
            viewModel.openBookmark(bookmark)
        }
    }
}

// MARK: - RepositoryGroupSection

private struct RepositoryGroupSection: View {

    @Environment(WindowViewModel.self) private var viewModel
    let group: BookmarkGroupData
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            RepositoryBookmarksList(bookmarks: viewModel.bookmarks(for: group.id))
        } label: {
            RepositoryGroupRow(group: group)
                .dropDestination(for: RepositoryBookmarkData.self) { items, _ in
                    for bookmark in items {
                        viewModel.moveBookmark(bookmark, toGroup: group.id)
                    }
                    return !items.isEmpty
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

// MARK: - Preview

#Preview {
    RepositoryGroupsSidebar()
        .environment(WindowViewModel(manager: MockRepositoryManager()))
        .frame(width: 220, height: 500)
}
