// Views/Repositories/RepositoryRow.swift
// Grove

import GroveKit
import SwiftUI

/// Browser sidebar row: repository or worktree name; the full path is in the tooltip.
struct RepositoryRow: View {

    let bookmark: RepositoryBookmarkData
    /// Set when the row is a linked worktree rather than a repository.
    var worktree: LinkedWorktree?
    /// Linked worktrees nested under this repository.
    var worktreeCount = 0
    @Environment(\.backgroundProminence) private var prominence

    /// On the accent selection highlight fixed tokens become unreadable; hierarchical styles adapt.
    private var isOnSelection: Bool { prominence == .increased }

    private var exists: Bool { !(worktree?.isMissing ?? false) && FileManager.default.fileExists(atPath: bookmark.path) }

    private var symbol: String {
        if !exists { return "questionmark.folder" }
        return worktree == nil ? "arrow.triangle.branch" : "tree"
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(isOnSelection ? AnyShapeStyle(.primary) : AnyShapeStyle(exists ? Theme.textSecondary : Theme.warning))
                .frame(width: 18)
            Text(bookmark.displayName)
                .font(.system(size: 13))
                .foregroundStyle(isOnSelection ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.textPrimary))
                .lineLimit(1)
                .truncationMode(.middle)
            if worktreeCount > 0 {
                Spacer(minLength: Theme.Spacing.xs)
                Label("\(worktreeCount)", systemImage: "tree")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(isOnSelection ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.textSecondary))
                    .help("\(worktreeCount) linked worktree\(worktreeCount == 1 ? "" : "s")")
            }
        }
        .padding(.vertical, 1)
        .help(tooltip)
    }

    private var tooltip: String {
        guard exists else { return "\(bookmark.path) no longer exists" }
        guard let worktree else { return bookmark.path }
        let main = URL(fileURLWithPath: worktree.mainRepositoryPath).lastPathComponent
        return "Worktree of \(main)\n\(bookmark.path)"
    }
}

#Preview {
    let bookmark = RepositoryBookmarkData(
        id: UUID(), path: "/Users/dev/Projects/my-app", displayName: "my-app",
        addedDate: Date(), lastOpenedDate: Date(), sortOrder: 0, groupID: nil
    )
    let worktree = LinkedWorktree(path: "/tmp/my-app-feature", mainRepositoryPath: bookmark.path, branch: "feature/login", isMissing: false)
    return List {
        RepositoryRow(bookmark: bookmark, worktreeCount: 2)
        RepositoryRow(bookmark: bookmark, worktree: worktree)
    }
    .listStyle(.sidebar)
    .frame(width: 240, height: 100)
}
