// Components/DiffViewer/DiffView.swift
// Grove
//
// The primary reusable diff renderer. Accepts a DiffResult and renders all
// hunks with headers, colored lines, and word-level highlights.
// Shared between WorkingCopy, History commit detail, Stashes, and Blame.

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
    /// Called when the user taps a hunk or line action button.
    var onHunkAction: ((HunkData, HunkAction) -> Void)?

    // MARK: State

    /// Lines selected for line-level staging. Keyed by line `id`.
    @State private var selectedLineIDs: Set<String> = []
    /// Pre-computed word-level highlights: (deletionID, additionID) → attributed strings.
    @State private var wordHighlights: [String: (AttributedString, AttributedString)] = [:]

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
            LazyVStack(spacing: 0) {
                ForEach(diff.hunks) { hunk in
                    hunkSection(hunk)
                }
            }
            .task { computeWordHighlights() }
        }
    }

    // MARK: Hunk Section

    @ViewBuilder
    private func hunkSection(_ hunk: HunkData) -> some View {
        let selectedInHunk = selectedLinesIn(hunk)

        DiffHunkHeaderView(
            hunk: hunk,
            showingStaged: showingStaged,
            hasSelectedLines: !selectedInHunk.isEmpty,
            // Read-only diffs (no handler) get a header without stage/discard buttons.
            onAction: onHunkAction == nil ? nil : { action in
                handleAction(action, hunk: hunk, selectedLines: selectedInHunk)
            }
        )

        ForEach(hunk.lines) { line in
            DiffLineView(
                line: line,
                attributedContent: attributedContent(for: line),
                isSelected: selectedLineIDs.contains(line.id)
            )
            .onTapGesture {
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

    private func attributedContent(for line: DiffLine) -> AttributedString? {
        let key = line.id
        if let pair = wordHighlights[key] {
            return line.type == .deletion ? pair.0 : pair.1
        }
        return nil
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
            onHunkAction?(hunk, action)
        case .stageLines, .unstageLines, .discardLines:
            // Line-level actions are handled via the ViewModel directly from DiffPanelView.
            // We just forward the hunk action upwards — the caller resolves which lines.
            onHunkAction?(hunk, action)
            selectedLineIDs.removeAll()
        }
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
        DiffView(diff: diff, showingStaged: false) { hunk, action in
            print("Hunk action: \(action) on \(hunk.header)")
        }
    }
    .frame(width: 700, height: 500)
    .background(Color(white: 0.11))
}
