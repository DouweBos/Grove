// Views/PullRequests/PRCommentView.swift
// Grove

import SwiftUI

/// One comment or review in a pull request conversation.
struct PRCommentView: View {

    let comment: PRComment

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(comment.authorName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if comment.isReview {
                    StatusBadge(title: "Review", symbol: "checkmark.seal.fill", tone: .neutral)
                }
                Spacer()
                Text(comment.createdDate, format: .relative(presentation: .named))
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
            }
            MarkdownRenderer(markdown: comment.body, fontSize: 13)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }
}

#Preview {
    VStack(spacing: 8) {
        ForEach(MockData.prComments) { PRCommentView(comment: $0) }
    }
    .padding()
    .frame(width: 440)
    .background(Theme.surface)
}
