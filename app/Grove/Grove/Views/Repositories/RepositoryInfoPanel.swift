// Views/Repositories/RepositoryInfoPanel.swift
// Grove
//
// Shown in the repository browser content area when a bookmark is selected.
// Displays repository metadata and provides a primary Open button.

import SwiftUI

// MARK: - RepositoryInfoPanel

/// Shows metadata and actions for the selected bookmarked repository.
struct RepositoryInfoPanel: View {

    @Environment(RepositoryBrowserViewModel.self) private var viewModel

    let bookmark: RepositoryBookmarkData

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "folder.fill.badge.gearshape")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange, .secondary)

                // Name & path
                VStack(spacing: 6) {
                    Text(bookmark.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(bookmark.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .truncationMode(.head)
                        .frame(maxWidth: 400)
                }

                // Metadata
                infoGrid

                // Actions
                HStack(spacing: 12) {
                    Button("Open") {
                        viewModel.openBookmark(bookmark)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Remove from List", role: .destructive) {
                        viewModel.removeBookmark(bookmark)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Info Grid

    private var infoGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                Text("Added")
                    .foregroundStyle(.secondary)
                    .gridColumnAlignment(.trailing)
                Text(bookmark.addedDate, style: .date)
            }
            if let lastOpened = bookmark.lastOpenedDate {
                GridRow {
                    Text("Last Opened")
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    Text(lastOpened, style: .relative)
                }
            }
        }
        .font(.callout)
    }
}

// MARK: - Preview

#Preview {
    let bookmark = RepositoryBookmarkData(
        id: UUID(),
        path: "/Users/dev/Projects/my-app",
        displayName: "my-app",
        addedDate: Calendar.current.date(byAdding: .day, value: -30, to: Date())!,
        lastOpenedDate: Calendar.current.date(byAdding: .hour, value: -2, to: Date()),
        sortOrder: 0,
        groupID: nil
    )
    let vm = RepositoryBrowserViewModel(manager: MockRepositoryManager())
    vm.selectedBookmarkID = bookmark.id
    return RepositoryInfoPanel(bookmark: bookmark)
        .environment(vm)
        .frame(width: 580, height: 500)
}
