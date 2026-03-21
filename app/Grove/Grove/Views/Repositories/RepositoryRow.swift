// Views/Repositories/RepositoryRow.swift
// Grove
//
// A single row in the repository browser sidebar representing
// one bookmarked repository. Compact single-line design.

import SwiftUI

// MARK: - RepositoryRow

/// Compact sidebar row for a bookmarked repository.
///
/// Shows only the folder icon and display name on one line, for a compact
/// sidebar aesthetic. The full path is surfaced via a tooltip on hover.
struct RepositoryRow: View {

    let bookmark: RepositoryBookmarkData

    var body: some View {
        Label {
            Text(bookmark.displayName)
                .lineLimit(1)
        } icon: {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .help(bookmark.path)
    }
}

// MARK: - Preview

#Preview {
    let bookmark = RepositoryBookmarkData(
        id: UUID(),
        path: "/Users/dev/Projects/my-app",
        displayName: "my-app",
        addedDate: Date(),
        lastOpenedDate: Date(),
        sortOrder: 0,
        groupID: nil
    )
    return List {
        RepositoryRow(bookmark: bookmark)
    }
    .frame(width: 220, height: 80)
}
