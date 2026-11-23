// History/Detail/ChangesetFiles.swift
// GroveUIKit
//
// Changed files that expand into their diffs, emitted as rows so the enclosing LazyVStack lays out only what shows.

#if os(macOS)
import GroveKit
import SwiftUI

struct ChangesetFiles: View {
    @Environment(\.gitStyle) private var style
    let files: [FileDiff]
    let expanded: Set<String>
    let toggle: (String) -> Void
    let options: GitDiffOptions
    /// Where a file's image versions are read from; nil shows images as binary.
    var images: GitDiffImages?
    var annotations: ((String) -> GitDiffAnnotations?)?
    let menu: (String) -> AnyView

    var body: some View {
        ForEach(files, id: \.path) { file in
            let isExpanded = expanded.contains(file.path)
            ChangesetFileRow(fileDiff: file, isExpanded: isExpanded) { toggle(file.path) }
                .contextMenu { menu(file.path) }
            if isExpanded { expandedDiff(file) }
        }
    }

    @ViewBuilder
    private func expandedDiff(_ file: FileDiff) -> some View {
        Group {
            if let images, GitImageDiffView.supports(path: file.path) {
                GitImageDiffView(images, path: file.path, oldPath: file.diff?.oldPath, mode: options.imageMode)
                    .frame(height: 360 * style.fontScale)
            } else if let diff = file.diff, diff.isBinary || !diff.hunks.isEmpty {
                GitDiffView(diff: diff, options: options, annotations: annotations?(file.path), fitsContent: true)
            } else {
                Text(file.status == .renamed ? "Renamed without content changes." : "No textual changes.")
                    .font(style.font(12))
                    .foregroundStyle(style.textSecondary)
                    .padding(GitMetrics.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: GitMetrics.Radius.tile))
        .overlay(RoundedRectangle(cornerRadius: GitMetrics.Radius.tile).strokeBorder(style.border, lineWidth: 0.5))
        .padding(.horizontal, GitMetrics.Spacing.md)
        .padding(.bottom, GitMetrics.Spacing.sm)
    }
}

/// A changed file: disclosure chevron, status badge, path and line counts.
struct ChangesetFileRow: View {
    @Environment(\.gitStyle) private var style
    let fileDiff: FileDiff
    var isExpanded = false
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: GitMetrics.Spacing.sm) {
                Image(systemName: "chevron.right")
                    .font(style.font(10, .semibold))
                    .foregroundStyle(style.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 10 * style.fontScale)
                CommitFileStatusBadge(status: fileDiff.status)
                pathText.lineLimit(1).truncationMode(.head)
                Spacer(minLength: GitMetrics.Spacing.sm)
                DiffStatsLabel(stats: fileDiff.stats)
                DiffStatsBar(stats: fileDiff.stats, width: 44 * style.fontScale)
            }
            .padding(.horizontal, GitMetrics.Spacing.lg)
            .frame(height: 32 * style.fontScale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gitClickable()
        .accessibilityHint(isExpanded ? "Collapse diff" : "Expand diff")
    }

    /// Directory in the secondary colour so the file name stands out.
    private var pathText: Text {
        let path = fileDiff.path as NSString
        let directory = path.deletingLastPathComponent
        let name = Text(path.lastPathComponent).foregroundStyle(style.textPrimary)
        let full = directory.isEmpty ? name : Text(directory + "/").foregroundStyle(style.textSecondary) + name
        return full.font(style.font(13))
    }
}

/// The app's diff options, or the view's own until it goes.
struct HistoryDiffOptions: DynamicProperty {
    @Environment(\.historyHost) private var host
    @State private var layout = GitDiffLayout.inline
    @State private var wraps = false
    @State private var image = GitImageDiffMode.sideBySide

    var options: GitDiffOptions {
        host.diffOptions ?? GitDiffOptions(layout: $layout, wrapsLines: $wraps, imageMode: $image)
    }
}

/// Unified/split and wrapping, for the diffs a panel shows.
struct HistoryDiffToggles: View {
    let options: GitDiffOptions

    var body: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            GitDiffLayoutPicker(layout: options.layout)
            GitWrapLinesToggle(isOn: options.wrapsLines)
        }
    }
}
#endif
