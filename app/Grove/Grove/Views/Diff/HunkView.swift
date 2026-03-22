// Views/Diff/HunkView.swift
// Grove
//
// Convenience wrapper combining DiffHunkHeaderView + DiffLineView rows
// for use in contexts outside WorkingCopy (e.g. History inline diffs).
// The WorkingCopy diff panel uses DiffView directly.

import SwiftUI

// MARK: - HunkView

/// Renders a single ``HunkData`` with its header and all lines.
///
/// Unlike ``DiffView`` this component renders only one hunk and does not
/// own selection state — suitable for embedding in `ForEach` loops inside
/// History or Stash detail panels where the parent controls selection.
struct HunkView: View {

    // MARK: Properties

    let hunk: HunkData
    var showingStaged: Bool = false
    var onAction: ((HunkAction) -> Void)?

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            DiffHunkHeaderView(
                hunk: hunk,
                showingStaged: showingStaged,
                hasSelectedLines: false,
                onAction: onAction
            )

            ForEach(hunk.lines) { line in
                DiffLineView(line: line)
            }
        }
    }
}

// MARK: - Preview

#Preview("Hunk View") {
    let hunk = MockData.diffResult(for: "Example.swift").hunks[0]
    ScrollView {
        HunkView(hunk: hunk, showingStaged: false) { action in
            print("Action: \(action)")
        }
    }
    .frame(width: 600, height: 300)
    .background(Color(white: 0.11))
}
