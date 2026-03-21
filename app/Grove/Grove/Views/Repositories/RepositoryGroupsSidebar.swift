// Views/Repositories/RepositoryGroupsSidebar.swift
// Grove
//
// Left sidebar of the repository browser showing collapsible groups
// with repository rows underneath each group.

import SwiftUI

// MARK: - RepositoryGroupsSidebar

/// Sidebar listing all bookmark groups with their repositories.
///
/// Groups are collapsible rows with an
/// orange folder icon; repos appear indented underneath.
///
/// Bookmark reordering across groups is supported via drag-and-drop.
/// Each ``RepositoryRow`` is draggable (payload: bookmark UUID string).
/// Each ``RepositoryGroupSection`` header and the ungrouped list are drop
/// targets that call ``RepositoryBrowserViewModel/moveBookmark(_:toGroup:)``.
struct RepositoryGroupsSidebar: View {

    @Environment(RepositoryBrowserViewModel.self) private var viewModel
    var body: some View {
        @Bindable var vm = viewModel
        List(selection: $vm.selectedBookmarkID) {
            Section("Repositories") {
                // Ungrouped bookmarks — also a drop target (moves into "no group").
                RepositoryBookmarksList(
                    bookmarks: viewModel.ungroupedBookmarks,
                    openBookmark: viewModel.openBookmark(_:),
                    removeBookmark: viewModel.removeBookmark(_:)
                )
                // Drop target: moving a bookmark here removes it from any group.
                .dropDestination(for: String.self) { items, _ in
                    guard let uuidString = items.first,
                          let id = UUID(uuidString: uuidString),
                          let bookmark = viewModel.manager.bookmarks.first(where: { $0.id == id })
                    else { return false }
                    viewModel.moveBookmark(bookmark, toGroup: nil)
                    return true
                }

                // Grouped bookmarks
                ForEach(viewModel.manager.bookmarkGroups.sorted(by: { $0.sortOrder < $1.sortOrder })) { group in
                    RepositoryGroupSection(group: group)
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    Button {
                        viewModel.sourceMode = .cloud
                    } label: {
                        Image(systemName: viewModel.sourceMode == .cloud ? "cloud.fill" : "cloud")
                    }
                    .help("Cloud Repositories")

                    Button {
                        viewModel.sourceMode = .local
                    } label: {
                        Image(systemName: viewModel.sourceMode == .local ? "externaldrive.fill" : "externaldrive")
                    }
                    .help("Local Repositories")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            SidebarBottomBar()
        }
    }
}

// MARK: - RepositoryGroupSection

private struct RepositoryGroupSection: View {

    @Environment(RepositoryBrowserViewModel.self) private var viewModel
    let group: BookmarkGroupData
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            RepositoryBookmarksList(
                bookmarks: viewModel.bookmarks(for: group.id),
                openBookmark: viewModel.openBookmark(_:),
                removeBookmark: viewModel.removeBookmark(_:)
            )
        } label: {
            RepositoryGroupRow(group: group)
                // Drop target on the group label: dropping a bookmark UUID here
                // moves it into this group.
                .dropDestination(for: String.self) { items, _ in
                    guard let uuidString = items.first,
                          let id = UUID(uuidString: uuidString),
                          let bookmark = viewModel.manager.bookmarks.first(where: { $0.id == id })
                    else { return false }
                    viewModel.moveBookmark(bookmark, toGroup: group.id)
                    return true
                }
        }
    }
}

// MARK: - RepositoryBookmarksList

private struct RepositoryBookmarksList: View {
    let bookmarks: [RepositoryBookmarkData]
    let openBookmark: (RepositoryBookmarkData) -> ()
    let removeBookmark: (RepositoryBookmarkData) -> ()

    var body: some View {
        ForEach(bookmarks) { bookmark in
            RepositoryRow(bookmark: bookmark)
                .tag(bookmark.id)
                // Drag source: the bookmark UUID string is the transfer payload.
                // Drop targets are the group section labels and the ungrouped list.
                .draggable(bookmark.id.uuidString)
                .onTapGesture(count: 2) {
                    openBookmark(bookmark)
                }
                .contextMenu {
                    Button("Open") {
                        openBookmark(bookmark)
                    }
                    Divider()
                    Button("Remove from List", role: .destructive) {
                        removeBookmark(bookmark)
                    }
                }
        }
    }
}

// MARK: - SidebarBottomBar

private struct SidebarBottomBar: View {
    var body: some View {
        HStack {
            // Placeholder for future add-group button (WS7 will wire keyboard shortcut)
            Spacer()
        }
        .frame(height: 28)
        .padding(.horizontal, 8)
        .background(.regularMaterial)
    }
}

// MARK: - Preview

#Preview {
    RepositoryGroupsSidebar()
        .environment(RepositoryBrowserViewModel(manager: MockRepositoryManager()))
        .frame(width: 220, height: 500)
}
