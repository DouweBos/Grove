// Views/Blame/BlameAnnotationColumn.swift
// Grove

import SwiftUI

// MARK: - BlameAnnotationColumn

/// Renders right-aligned blame annotation blocks beside the source code.
///
/// Contiguous lines that share the same commit are represented as a single
/// block spanning their combined height. Each block shows:
/// - Commit summary (first line of the commit message)
/// - Author name
/// - Relative date (e.g. "3 months ago")
struct BlameAnnotationColumn: View {

    // MARK: - Properties

    /// Blame entries in line-start order, as returned by the repository.
    let entries: [BlameEntry]

    /// Total number of source lines (used to compute block heights).
    let lineCount: Int

    // MARK: - Constants

    private static let lineHeight: CGFloat = 18
    private static let blockPadding: CGFloat = 4

    // MARK: - Body

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(entries) { entry in
                BlameAnnotationBlock(entry: entry, lineHeight: Self.lineHeight)
            }

            // Fill any remaining lines after the last block.
            let coveredLines = entries.reduce(0) { $0 + $1.lineCount }
            let remainingLines = max(0, lineCount - coveredLines)
            if remainingLines > 0 {
                Spacer()
                    .frame(height: CGFloat(remainingLines) * Self.lineHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// MARK: - BlameAnnotationBlock

/// A single blame annotation block covering one or more contiguous lines.
private struct BlameAnnotationBlock: View {

    let entry: BlameEntry
    let lineHeight: CGFloat

    var body: some View {
        let blockHeight = CGFloat(entry.lineCount) * lineHeight

        HStack(alignment: .top, spacing: 0) {
            // Left border accent
            Rectangle()
                .fill(Color.accentColor.opacity(0.3))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 1) {
                // Commit summary — truncated to one line.
                Text(entry.summary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Author and relative date on a second line.
                HStack(spacing: 4) {
                    Text(entry.authorName)
                    Text("\u{00B7}")   // middle dot separator
                    Text(entry.authorDate, style: .relative)
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
        }
        .frame(height: max(blockHeight, lineHeight * 2), alignment: .top)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(3)
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
    }
}

// MARK: - Preview

#Preview {
    let entries = MockData.blameEntries
    let lineCount = entries.reduce(0) { $0 + $1.lineCount }

    ScrollView {
        BlameAnnotationColumn(entries: entries, lineCount: lineCount + 5)
    }
    .frame(width: 260, height: 400)
    .background(Color(NSColor.textBackgroundColor))
}
