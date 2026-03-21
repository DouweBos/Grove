// Views/PullRequests/PRCommentView.swift
// Grove

import SwiftUI

/// A single comment or review in the pull request detail panel.
///
/// Shows the author avatar, name, date, a review indicator, and the comment body.
struct PRCommentView: View {

    let comment: PRComment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header row
            HStack(alignment: .center, spacing: 8) {
                PRAuthorAvatarView(name: comment.authorName)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(comment.authorName)
                            .font(.caption)
                            .fontWeight(.semibold)

                        if comment.isReview {
                            reviewBadge
                        }
                    }

                    Text(comment.createdDate, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }

            // Comment body
            MarkdownRenderer(markdown: comment.body, fontSize: 13)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Review Badge

    private var reviewBadge: some View {
        Label("Review", systemImage: "checkmark.seal.fill")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.purple, in: Capsule())
    }
}

#Preview {
    VStack(spacing: 8) {
        ForEach(MockData.prComments) { comment in
            PRCommentView(comment: comment)
        }
    }
    .padding()
    .frame(width: 420)
}
