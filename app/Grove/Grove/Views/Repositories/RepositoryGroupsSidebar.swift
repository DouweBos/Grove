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
struct RepositoryGroupsSidebar: View {

    @Environment(RepositoryBrowserViewModel.self) private var viewModel
    var body: some View {
        @Bindable var vm = viewModel
        List(selection: $vm.selectedBookmarkID) {
            RepositoryBookmarksList(
                bookmarks: viewModel.ungroupedBookmarks,
                openBookmark: viewModel.openBookmark(_:),
                removeBookmark: viewModel.removeBookmark(_:)
            )

            // Grouped bookmarks
            ForEach(viewModel.manager.bookmarkGroups.sorted(by: { $0.sortOrder < $1.sortOrder })) { group in
                RepositoryGroupSection(group: group)
            }
        }
        .listStyle(.sidebar)
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
        }
    }
}

private struct RepositoryBookmarksList: View {
    let bookmarks: [RepositoryBookmarkData]
    let openBookmark: (RepositoryBookmarkData) -> ()
    let removeBookmark: (RepositoryBookmarkData) -> ()
    
    var body: some View {
        ForEach(bookmarks) { bookmark in
            RepositoryRow(bookmark: bookmark)
                .tag(bookmark.id)
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
