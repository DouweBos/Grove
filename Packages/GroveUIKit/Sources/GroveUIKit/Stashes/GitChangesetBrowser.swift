// Stashes/GitChangesetBrowser.swift
// GroveUIKit
//
// A read-only file list over the selected file's diff, e.g. a stash's or a pull request's changes.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitChangesetBrowser: View {
    @Environment(\.gitStyle) private var style
    private let files: [FileDiff]
    private let selectedPath: String?
    private let isLoading: Bool
    private let emptyTitle: String
    private let images: GitDiffImages?
    private let appOptions: GitDiffOptions?
    private let onSelect: (FileDiff) -> Void
    @State private var layout = GitDiffLayout.inline
    @State private var wraps = false
    @State private var imageMode = GitImageDiffMode.sideBySide

    /// - Parameters:
    ///   - images: Lets image files show as pictures; without it they show as binary.
    ///   - options: The app's diff options, so they match its other diffs; nil keeps them for the view's life.
    public init(files: [FileDiff], selectedPath: String?, isLoading: Bool = false, emptyTitle: String = "No Changes",
                images: GitDiffImages? = nil, options: GitDiffOptions? = nil, onSelect: @escaping (FileDiff) -> Void) {
        self.files = files
        self.selectedPath = selectedPath
        self.isLoading = isLoading
        self.emptyTitle = emptyTitle
        self.images = images
        appOptions = options
        self.onSelect = onSelect
    }

    private var options: GitDiffOptions {
        appOptions ?? GitDiffOptions(layout: $layout, wrapsLines: $wraps, imageMode: $imageMode)
    }

    public var body: some View {
        if isLoading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if files.isEmpty {
            GitEmptyState(systemImage: "doc.text.magnifyingglass", title: emptyTitle)
        } else {
            VStack(spacing: 0) {
                fileList
                Rectangle().fill(style.border).frame(height: 0.5)
                diffArea
            }
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.xs) {
            GitSectionLabel(title: "Changed Files", count: files.count) {
                Text("+\(totals.additions)  \u{2212}\(totals.deletions)")
                    .font(style.monoCaption)
                    .foregroundStyle(style.textSecondary)
                GitWrapLinesToggle(isOn: options.wrapsLines)
                GitDiffLayoutPicker(layout: options.layout)
            }
            .padding(.horizontal, GitMetrics.Spacing.lg)
            .padding(.top, GitMetrics.Spacing.md)
            GitSelectableList(items: files.map(ChangesetItem.init), selection: selectedPath, onSelect: { onSelect($0.file) }) {
                ChangesetFileLine(file: $0.file)
            }
        }
        .frame(height: min(CGFloat(files.count) * 32 * style.fontScale + 56 * style.fontScale, 220 * style.fontScale))
    }

    @ViewBuilder
    private var diffArea: some View {
        if let file = files.first(where: { $0.path == selectedPath }) {
            if let images, GitImageDiffView.supports(path: file.path) {
                GitImageDiffView(images, path: file.path, oldPath: file.diff?.oldPath, mode: options.imageMode)
            } else if let diff = file.diff {
                GitDiffView(diff: diff, options: options).id(file.path)
            } else {
                GitEmptyState(systemImage: "doc.zipper", title: "No Diff Available", subtitle: "Binary or unchanged file.")
            }
        } else {
            GitEmptyState(systemImage: "doc.text", title: "Select a File", subtitle: "Choose a file above to see its changes.")
        }
    }

    private var totals: (additions: Int, deletions: Int) {
        files.reduce((0, 0)) { ($0.0 + $1.stats.additions, $0.1 + $1.stats.deletions) }
    }
}

private struct ChangesetItem: Identifiable {
    let file: FileDiff
    var id: String { file.path }
}

/// One file in a changeset: status glyph, name, dimmed directory, mono +/- counts.
struct ChangesetFileLine: View {
    @Environment(\.gitStyle) private var style
    let file: FileDiff

    var body: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            Image(systemName: symbol)
                .font(style.font(12, .semibold))
                .foregroundStyle(color)
                .frame(width: 16 * style.fontScale)
            Text((file.path as NSString).lastPathComponent)
                .font(style.font(13, .medium))
                .foregroundStyle(style.textPrimary)
                .lineLimit(1)
            Text((file.path as NSString).deletingLastPathComponent)
                .font(style.monoCaption)
                .foregroundStyle(style.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: GitMetrics.Spacing.sm)
            if file.stats.additions > 0 {
                Text("+\(file.stats.additions)").font(style.monoCaption).foregroundStyle(style.success)
            }
            if file.stats.deletions > 0 {
                Text("\u{2212}\(file.stats.deletions)").font(style.monoCaption).foregroundStyle(style.danger)
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
        case .added, .untracked: style.success
        case .deleted: style.danger
        case .renamed, .copied: style.renamed
        default: style.info
        }
    }
}
#endif
