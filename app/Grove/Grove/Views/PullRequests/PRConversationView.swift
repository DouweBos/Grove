// Views/PullRequests/PRConversationView.swift
// Grove

import GroveKit
import SwiftUI

/// The pull request's comments and line comments, with a composer for a new comment.
struct PRConversationView: View {

    @Environment(PullRequestsViewModel.self) private var viewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionLabel(title: "Conversation", count: viewModel.comments.count)
                if viewModel.isLoadingComments {
                    ProgressView().controlSize(.small)
                } else if viewModel.comments.isEmpty {
                    Text("No comments yet.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(viewModel.comments) { PRCommentView(comment: $0) }
                }
            }
            if !viewModel.reviewThreads.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionLabel(title: "Line Comments", count: viewModel.reviewThreads.count)
                    ForEach(viewModel.reviewThreads) { PRReviewThreadView(thread: $0) }
                }
            }
            composer
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel(title: "Add a Comment")
            MultilineField(text: viewModel.commentDraft, placeholder: "Write a comment (Markdown)", height: 90,
                           onChange: viewModel.setCommentDraft)
            if let error = viewModel.commentError {
                Banner(symbol: "xmark.octagon", message: error, tone: .negative)
            }
            HStack(spacing: Theme.Spacing.sm) {
                Spacer()
                if viewModel.isPostingComment { ProgressView().controlSize(.small) }
                Button("Comment") { Task { await viewModel.postComment() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canPostComment)
            }
        }
    }
}

/// A line comment with its replies, under the diff lines it points at.
struct PRReviewThreadView: View {
    let thread: PRReviewThread

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "doc.text").foregroundStyle(Theme.textSecondary)
                Text(location).font(.monoCaption).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.head)
            }
            if !thread.context.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(thread.context.enumerated()), id: \.offset) { _, line in
                        Text(line.isEmpty ? " " : line)
                            .font(.monoCaption)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .background(fill(for: line))
                    }
                }
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.tile))
            }
            ForEach([thread.root] + thread.replies) { comment in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text(comment.authorName).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(comment.createdDate, format: .relative(presentation: .named))
                            .font(.monoCaption).foregroundStyle(Theme.textSecondary)
                    }
                    MarkdownRenderer(markdown: comment.body, fontSize: 13)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.leading, comment.replyTo == nil ? 0 : Theme.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }

    private var location: String {
        thread.root.line.map { "\(thread.root.path):\($0)" } ?? "\(thread.root.path) (outdated)"
    }

    private func fill(for line: String) -> Color {
        if line.hasPrefix("+") { return Theme.addedFill }
        if line.hasPrefix("-") { return Theme.deletedFill }
        return .clear
    }
}

#Preview {
    let vm = PullRequestsViewModel(repository: MockGitRepository())
    return ScrollView {
        PRConversationView().padding()
    }
    .environment(vm)
    .frame(width: 560, height: 700)
    .background(Theme.surface)
    .task {
        await vm.refresh()
        if let first = vm.pullRequests.first { await vm.select(first) }
    }
}
