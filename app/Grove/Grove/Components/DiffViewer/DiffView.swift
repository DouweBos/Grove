// Components/DiffViewer/DiffView.swift
// Grove
//
// The primary reusable diff renderer. Accepts a DiffResult and renders all
// hunks with headers, colored lines, and word-level highlights.
// Shared between WorkingCopy, History commit detail, Stashes, and Blame.

import AppKit
import SwiftUI

// MARK: - DiffView

/// Renders a complete ``DiffResult`` with hunk headers, colored lines, and
/// optional hunk/line-level action buttons.
///
/// The view is scroll-container-agnostic — embed inside a `ScrollView` at the
/// call site. The `DiffPanelView` wraps this inside its own scroll view.
///
/// ```swift
/// ScrollView {
///     DiffView(diff: result, showingStaged: false) { hunk, action in
///         await viewModel.perform(action, on: hunk)
///     }
/// }
/// ```
struct DiffView: View {

    // MARK: Properties

    let diff: DiffResult
    /// Whether the panel is in Staged mode (affects hunk action button labels).
    var showingStaged: Bool = false
    /// Hunk or line action; lines are the selected ones for line actions, empty for whole hunks.
    /// `nil` hides the action buttons.
    var onHunkAction: ((HunkAction, HunkData, [DiffLine]) -> Void)?

    @Environment(\.diffViewportWidth) private var viewportWidth

    // MARK: State

    /// Estimated width of the longest line, so short lines paint their background across it too.
    @State private var contentWidth: CGFloat = 0

    /// Lines selected for line-level staging. Keyed by line `id`.
    @State private var selectedLineIDs: Set<String> = []
    /// Pre-computed word-level highlights: (deletionID, additionID) → attributed strings.
    @State private var wordHighlights: [String: (AttributedString, AttributedString)] = [:]
    /// Syntax colors, lexed per hunk as its lines scroll into view.
    @State private var syntax = DiffSyntaxCache()

    // MARK: Body

    var body: some View {
        if diff.isBinary {
            binaryPlaceholder
        } else if diff.hunks.isEmpty {
            EmptyStateView(
                systemImage: "checkmark.circle",
                title: "No Changes",
                subtitle: "This file has no differences to display."
            )
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(diff.hunks) { hunk in
                    hunkSection(hunk)
                }
            }
            .frame(width: viewportWidth.map { max($0, contentWidth) }, alignment: .leading)
            .task(id: diff.hunks) {
                selectedLineIDs.removeAll()
                contentWidth = Self.estimatedWidth(of: diff.hunks)
                computeWordHighlights()
            }
        }
    }

    // MARK: Hunk Section

    @ViewBuilder
    private func hunkSection(_ hunk: HunkData) -> some View {
        let selectedInHunk = selectedLinesIn(hunk)
        let syntaxKey = DiffSyntaxCache.key(for: hunk, path: diff.filePath)

        DiffHunkHeaderView(
            hunk: hunk,
            showingStaged: showingStaged,
            hasSelectedLines: !selectedInHunk.isEmpty,
            onAction: onHunkAction == nil ? nil : { action in
                handleAction(action, hunk: hunk, selectedLines: selectedInHunk)
            }
        )

        ForEach(hunk.lines) { line in
            DiffLineView(
                line: line,
                attributedContent: attributedContent(for: line, in: hunk, syntaxKey: syntaxKey),
                isSelected: selectedLineIDs.contains(line.id)
            )
            .onTapGesture {
                guard onHunkAction != nil else { return }
                toggleLineSelection(line)
            }
        }
    }

    // MARK: Binary Placeholder

    private var binaryPlaceholder: some View {
        EmptyStateView(
            systemImage: "doc.zipper",
            title: "Binary File",
            subtitle: "Diff is not available for binary files."
        )
    }

    // MARK: Word Highlight Lookup

    /// Word-level change highlights with syntax colors on top of them.
    private func attributedContent(for line: DiffLine, in hunk: HunkData, syntaxKey: DiffSyntaxCache.HunkKey?) -> AttributedString? {
        let word = wordHighlights[line.id].map { line.type == .deletion ? $0.0 : $0.1 }
        return syntax.attributed(for: line, in: hunk, key: syntaxKey, wordHighlight: word)
    }

    // MARK: Line Selection

    private func toggleLineSelection(_ line: DiffLine) {
        guard line.type != .context else { return }
        if selectedLineIDs.contains(line.id) {
            selectedLineIDs.remove(line.id)
        } else {
            selectedLineIDs.insert(line.id)
        }
    }

    private func selectedLinesIn(_ hunk: HunkData) -> [DiffLine] {
        hunk.lines.filter { selectedLineIDs.contains($0.id) }
    }

    // MARK: Action Handling

    private func handleAction(_ action: HunkAction, hunk: HunkData, selectedLines: [DiffLine]) {
        switch action {
        case .stageHunk, .unstageHunk, .discardHunk:
            onHunkAction?(action, hunk, [])
        case .stageLines, .unstageLines, .discardLines:
            onHunkAction?(action, hunk, selectedLines)
        }
        selectedLineIDs.removeAll()
    }

    // MARK: Width Estimate

    private static let characterWidth = ("0" as NSString)
        .size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]).width

    /// Monospaced, so character count is enough; tabs count as four columns.
    static func estimatedWidth(of hunks: [HunkData]) -> CGFloat {
        let longest = hunks.lazy.flatMap(\.lines).map { line in
            line.content.count + line.content.reduce(0) { $1 == "\t" ? $0 + 3 : $0 }
        }.max() ?? 0
        return DiffLineView.gutterWidth + CGFloat(longest) * characterWidth + Theme.Spacing.xl
    }

    // MARK: Word Highlights Computation

    /// Pairs adjacent deletion + addition lines within each hunk and computes
    /// word-level highlights for each pair. Run once after the diff loads.
    private func computeWordHighlights() {
        var result: [String: (AttributedString, AttributedString)] = [:]
        for hunk in diff.hunks {
            let deletions = hunk.lines.filter { $0.type == .deletion }
            let additions = hunk.lines.filter { $0.type == .addition }
            // Pair up deletions with additions positionally.
            let pairCount = min(deletions.count, additions.count)
            for i in 0..<pairCount {
                let del = deletions[i]
                let add = additions[i]
                let (delAttr, addAttr) = DiffWordHighlighter.highlight(
                    deletion: del.content,
                    addition: add.content
                )
                result[del.id] = (delAttr, addAttr)
                result[add.id] = (delAttr, addAttr)
            }
        }
        wordHighlights = result
    }
}

// MARK: - Preview

#Preview("Diff View") {
    let diff = MockData.diffResult(for: "WorkingCopyViewModel.swift")
    ScrollView {
        DiffView(diff: diff, showingStaged: false) { _, _, _ in }
    }
    .frame(width: 700, height: 500)
    .background(Theme.surface)
}
