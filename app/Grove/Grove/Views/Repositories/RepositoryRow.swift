// Views/Repositories/RepositoryRow.swift
// Grove
//
// A single row in the repository browser sidebar representing
// one bookmarked repository.

import SwiftUI

// MARK: - RepositoryRow

/// Sidebar row for a bookmarked repository — folder icon + display name.
struct RepositoryRow: View {

    let bookmark: RepositoryBookmarkData

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(bookmark.displayName)
                    .lineLimit(1)
                Text(bookmark.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        } icon: {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 4)
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
    .frame(width: 220, height: 120)
}
