// Views/History/InlineCommitDiffView.swift
// Grove

import SwiftUI

/// Read-only diff inside a bordered tile, for commit-like content (stashes, pull requests).
struct InlineCommitDiffView: View {
    let diff: DiffResult

    var body: some View {
        DiffView(diff: diff)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.tile).strokeBorder(Theme.border, lineWidth: 0.5))
            .padding(.vertical, Theme.Spacing.xs)
    }
}

#Preview {
    ScrollView {
        InlineCommitDiffView(diff: MockData.diffResult(for: "WorkingCopyViewModel.swift"))
    }
    .frame(width: 520, height: 400)
    .padding()
    .background(Theme.surface)
}
