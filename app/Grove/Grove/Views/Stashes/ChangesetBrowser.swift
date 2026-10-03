// Views/Stashes/ChangesetBrowser.swift
// Grove
//
// Read-only file list + diff, shared by the Stashes and Pull Request detail cards.

import GroveKit
import SwiftUI

struct ChangesetBrowser: View {
    let files: [FileDiff]
    let selectedPath: String?
    var isLoading = false
    var emptyTitle = "No Changes"
    /// Lets image files render as pictures; without it they show the binary placeholder.
    var imageSource: ImageDiffSource?
    let onSelect: (FileDiff) -> Void

    var body: some View {
        if isLoading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if files.isEmpty {
            EmptyStateView(systemImage: "doc.text.magnifyingglass", title: emptyTitle)
        } else {
            VStack(spacing: 0) {
                fileList
                Rectangle().fill(Theme.border).frame(height: 0.5)
                diffArea
            }
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            SectionLabel(title: "Changed Files", count: files.count) {
                Text("+\(totals.additions)  \u{2212}\(totals.deletions)")
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                WrapLinesToggle()
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
            SelectableList(items: files.map(ChangesetRowItem.init), selection: selectedPath,
                           onSelect: { onSelect($0.file) }) { item in
                ChangesetFileLine(file: item.file)
            }
        }
        .frame(height: min(CGFloat(files.count) * 32 + 56, 220))
    }

    @ViewBuilder
    private var diffArea: some View {
        if let file = files.first(where: { $0.path == selectedPath }) {
            if let imageSource, ImageDiffView.supports(path: file.path) {
                RepositoryImageDiffView(source: imageSource, path: file.path, oldPath: file.diff?.oldPath)
            } else if let diff = file.diff {
                DiffScrollView { DiffView(diff: diff) }
                    .id(file.path)
            } else {
                EmptyStateView(systemImage: "doc.zipper", title: "No Diff Available",
                               subtitle: "Binary or unchanged file.")
            }
        } else {
            EmptyStateView(systemImage: "doc.text", title: "Select a File",
                           subtitle: "Choose a file above to see its changes.")
        }
    }

    private var totals: (additions: Int, deletions: Int) {
        files.reduce((0, 0)) { ($0.0 + $1.stats.additions, $0.1 + $1.stats.deletions) }
    }
}

private struct ChangesetRowItem: Identifiable {
    let file: FileDiff
    var id: String { file.path }
}

/// One file in a changeset: status glyph, name, dimmed directory, mono +/- counts.
struct ChangesetFileLine: View {
    let file: FileDiff

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)
            Text((file.path as NSString).lastPathComponent)
                .font(.rowTitle)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text((file.path as NSString).deletingLastPathComponent)
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: Theme.Spacing.sm)
            if file.stats.additions > 0 {
                Text("+\(file.stats.additions)").font(.monoCaption).foregroundStyle(Theme.added)
            }
            if file.stats.deletions > 0 {
                Text("\u{2212}\(file.stats.deletions)").font(.monoCaption).foregroundStyle(Theme.deleted)
            }
        }
    }

    private var symbol: String {
        switch file.status {
        case .added, .untracked: "plus.circle.fill"
        case .deleted: "minus.circle.fill"
        case .renamed, .copied: "arrow.right.circle.fill"
        default: "pencil.circle.fill"
        }
    }

    private var color: Color {
        switch file.status {
        case .added, .untracked: Theme.added
        case .deleted: Theme.deleted
        case .renamed, .copied: Theme.renamed
        default: Theme.modified
        }
    }
}

#Preview {
    ChangesetBrowser(files: MockData.commitFileDiffs, selectedPath: MockData.commitFileDiffs.first?.path) { _ in }
        .frame(width: 560, height: 520)
        .panel()
        .padding()
        .background(Theme.background)
}
