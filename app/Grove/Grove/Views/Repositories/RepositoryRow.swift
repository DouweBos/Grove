// Views/Repositories/RepositoryRow.swift
// Grove

import SwiftUI

/// Browser sidebar row: repository name; the full path is in the tooltip.
struct RepositoryRow: View {

    let bookmark: RepositoryBookmarkData
    @Environment(\.backgroundProminence) private var prominence

    /// On the accent selection highlight fixed tokens become unreadable; hierarchical styles adapt.
    private var isOnSelection: Bool { prominence == .increased }

    private var exists: Bool { FileManager.default.fileExists(atPath: bookmark.path) }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: exists ? "arrow.triangle.branch" : "questionmark.folder")
                .font(.system(size: 12))
                .foregroundStyle(isOnSelection ? AnyShapeStyle(.primary) : AnyShapeStyle(exists ? Theme.textSecondary : Theme.warning))
                .frame(width: 18)
            Text(bookmark.displayName)
                .font(.system(size: 13))
                .foregroundStyle(isOnSelection ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.textPrimary))
                .lineLimit(1)
        }
        .padding(.vertical, 1)
        .help(exists ? bookmark.path : "\(bookmark.path) no longer exists")
    }
}

#Preview {
    let bookmark = RepositoryBookmarkData(
        id: UUID(), path: "/Users/dev/Projects/my-app", displayName: "my-app",
        addedDate: Date(), lastOpenedDate: Date(), sortOrder: 0, groupID: nil
    )
    return List {
        RepositoryRow(bookmark: bookmark)
    }
    .listStyle(.sidebar)
    .frame(width: 240, height: 80)
}
