// Conflicts/ConflictVersionPanel.swift
// GroveUIKit
//
// One side of the resolver: which branch it comes from, the file on that side, and a button to keep it.

#if os(macOS)
import GroveKit
import SwiftUI

struct ConflictVersionPanel: View {
    @Environment(\.gitStyle) private var style
    let side: ConflictSide
    let branchName: String
    /// Nil while loading; `.some(nil)` when this side deleted the file.
    let content: String??
    let isBusy: Bool
    var onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: GitMetrics.Spacing.sm) {
                Circle().fill(style.lane(side == .ours ? 0 : 1)).frame(width: 8, height: 8)
                Text(side == .ours ? "Current" : "Incoming")
                    .font(style.sectionLabel)
                    .foregroundStyle(style.textSecondary)
                GitBranchLabel(name: branchName, kind: .localBranch(isHEAD: side == .ours))
                Spacer(minLength: GitMetrics.Spacing.sm)
                Button(side == .ours ? "Keep Current" : "Take Incoming", action: onSelect)
                    .controlSize(.small)
                    .disabled(content == nil || isBusy)
                    .gitClickable()
            }
            .padding(.horizontal, GitMetrics.Spacing.md)
            .frame(height: 40 * style.fontScale)
            .overlay(alignment: .bottom) { Rectangle().fill(style.border).frame(height: 0.5) }

            preview.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .gitPanel()
    }

    @ViewBuilder
    private var preview: some View {
        switch content {
        case .none:
            ProgressView().controlSize(.small)
        case .some(.none):
            GitEmptyState(systemImage: "trash", title: "Deleted", subtitle: "This side removed the file.")
        case .some(.some(let text)) where text.looksBinary:
            GitEmptyState(systemImage: "doc.zipper", title: "Binary File", subtitle: "Keep a side to resolve it.")
        case .some(.some(let text)):
            ConflictTextView(text: .constant(text), isEditable: false)
                .background(style.background.opacity(0.5))
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        ConflictVersionPanel(side: .ours, branchName: "main", content: .some("let a = 1\n"), isBusy: false) {}
        ConflictVersionPanel(side: .theirs, branchName: "feature/auth", content: .some(nil), isBusy: false) {}
    }
    .frame(width: 700, height: 360)
    .padding()
}
#endif
