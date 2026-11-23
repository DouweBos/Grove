// History/Parts/GitCommitRow.swift
// GroveUIKit
//
// One commit as History lists it, for a short list elsewhere such as a stack's layer.

#if os(macOS)
import GroveKit
import SwiftUI

public struct GitCommitRow: View {
    @Environment(\.gitStyle) private var style
    private let commit: CommitInfo

    public init(commit: CommitInfo) {
        self.commit = commit
    }

    public var body: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            CommitAvatar(name: commit.authorName, email: commit.authorEmail, size: .medium)
            VStack(alignment: .leading, spacing: 3) {
                Text(commit.summary)
                    .font(style.font(13, .medium))
                    .foregroundStyle(style.textPrimary)
                    .lineLimit(1)
                HStack(spacing: GitMetrics.Spacing.xs) {
                    Text("\(commit.shortSHA) · \(commit.authorName) · \(commit.authorDate.commitRelative())").lineLimit(1)
                    if commit.isMerge { Image(systemName: "arrow.triangle.merge").accessibilityLabel("Merge commit") }
                }
                .font(style.monoCaption)
                .foregroundStyle(style.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GitMetrics.Spacing.md)
        .frame(height: 46 * style.fontScale)
        .contentShape(Rectangle())
    }
}
#endif
