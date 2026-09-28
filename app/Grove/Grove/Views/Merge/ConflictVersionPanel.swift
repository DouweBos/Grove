// Views/Merge/ConflictVersionPanel.swift
// Grove
//
// One side of the conflict resolver: which branch it comes from, the file's
// content on that side, and a button to keep it.

import SwiftUI

struct ConflictVersionPanel: View {
    let side: ConflictSide
    let branchName: String
    /// `nil` while loading; `.some(nil)` when this side deleted the file.
    let content: String??
    var onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle().fill(sideColor).frame(width: 8, height: 8)
                Text(side == .ours ? "Current" : "Incoming")
                    .font(.sectionLabel)
                    .foregroundStyle(Theme.textSecondary)
                BranchLabel(name: branchName, kind: .localBranch(isHEAD: side == .ours))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: 40)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }

            preview

            Button(action: onSelect) {
                Text(side == .ours ? "Keep Current" : "Take Incoming")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .padding(Theme.Spacing.md)
            .disabled(content == nil)
        }
        .panel()
    }

    @ViewBuilder
    private var preview: some View {
        switch content {
        case .none:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .some(.none):
            EmptyStateView(systemImage: "trash", title: "Deleted", subtitle: "This side removed the file.")
        case .some(.some(let text)):
            CanvasScrollView {
                Text(verbatim: text)
                    .font(.monoBody)
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                    .padding(Theme.Spacing.md)
            }
            .background(Theme.background.opacity(0.5))
        }
    }

    private var sideColor: Color { side == .ours ? Theme.laneColor(0) : Theme.laneColor(1) }
}

#Preview {
    HStack(spacing: Theme.Spacing.md) {
        ConflictVersionPanel(side: .ours, branchName: "main", content: .some("let a = 1\n")) {}
        ConflictVersionPanel(side: .theirs, branchName: "feature/auth", content: .some(nil)) {}
    }
    .frame(width: 700, height: 360)
    .padding()
    .background(Theme.background)
}
