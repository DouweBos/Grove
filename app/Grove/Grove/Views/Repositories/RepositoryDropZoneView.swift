// Views/Repositories/RepositoryDropZoneView.swift
// Grove
//
// Browser welcome state: a folder drop target, the three ways to add
// a repository, and recently opened repositories.

import SwiftUI

struct RepositoryDropZoneView: View {

    @Environment(WindowViewModel.self) private var viewModel
    @State private var isTargeted = false

    private var recent: [RepositoryBookmarkData] {
        viewModel.manager.bookmarks
            .filter { $0.displayLastOpenedDate != nil }
            .sorted { ($0.displayLastOpenedDate ?? .distantPast) > ($1.displayLastOpenedDate ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                VStack(spacing: Theme.Spacing.xs) {
                    Text("Repositories")
                        .font(.pageTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Select a repository in the sidebar, or bring in a new one.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                dropZone
                actions
                if !recent.isEmpty { recentCard }
            }
            .frame(maxWidth: 560)
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: Drop Zone

    private var dropZone: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(isTargeted ? Theme.accent : Theme.textSecondary)
            Text("Drop a repository folder here")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("It's added to your list without being moved.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(isTargeted ? Theme.selectionFill : Theme.surface,
                    in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(isTargeted ? Theme.accent : Theme.border, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .dropDestination(for: URL.self) { urls, _ in
            viewModel.handleDroppedURLs(urls)
            return !urls.isEmpty
        } isTargeted: { isTargeted = $0 }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: Theme.Spacing.md) {
            ActionTile(title: "Add Existing", detail: "A folder on this Mac", symbol: "folder.badge.plus") {
                viewModel.showAddDialog()
            }
            ActionTile(title: "Clone", detail: "From a remote URL", symbol: "square.and.arrow.down") {
                viewModel.showCloneDialog()
            }
            ActionTile(title: "New", detail: "An empty repository", symbol: "plus.square.on.square") {
                viewModel.showCreateDialog()
            }
        }
    }

    // MARK: Recent

    private var recentCard: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Recently Opened")
            ForEach(recent) { bookmark in
                Button { viewModel.openBookmark(bookmark) } label: {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(Theme.accent)
                            .frame(width: 18)
                        Text(bookmark.displayName)
                            .font(.rowTitle)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: Theme.Spacing.sm)
                        if let date = bookmark.displayLastOpenedDate {
                            Text(date, format: .relative(presentation: .named))
                                .font(.monoCaption)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm + 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(abbreviatingHome(bookmark.path))
            }
        }
        .panel()
    }
}

// MARK: - ActionTile

private struct ActionTile: View {
    let title: String
    let detail: String
    let symbol: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
            .background(isHovered ? Theme.surfaceRaised : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

#Preview {
    RepositoryDropZoneView()
        .environment(WindowViewModel(manager: MockRepositoryManager()))
        .frame(width: 700, height: 600)
}
