// PRCommentingTests.swift
// GroveTests

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct PRCommentingTests {

    // Two lines of `gh api .../pulls/N/comments --paginate --jq '.[]'`, a comment and its reply.
    private let output = [
        #"{"id":10,"user":{"login":"alice"},"body":"Rename this","path":"a.swift","line":12,"original_line":12,"#
            + #""diff_hunk":"@@ -1,3 +1,4 @@\n let a = 1\n-let b = 2\n+let bee = 2\n+let c = 3","created_at":"2026-09-01T10:00:00Z"}"#,
        #"{"id":11,"in_reply_to_id":10,"user":{"login":"bob"},"body":"Done","path":"a.swift","line":null,"original_line":12,"#
            + #""created_at":"2026-09-01T11:00:00Z"}"#
    ].joined(separator: "\n")

    @Test func parsesGitHubLineComments() throws {
        let comments = try PRReviewComment.parseGitHub(output)
        #expect(comments.map(\.id) == [10, 11])
        #expect(comments[0].authorName == "alice")
        #expect(comments[0].line == 12)
        #expect(comments[1].replyTo == 10)
        // An outdated comment falls back to the line it was made on.
        #expect(comments[1].line == 12)
        #expect(try PRReviewComment.parseGitHub("").isEmpty)
    }

    @Test func repliesJoinTheirThread() throws {
        let threads = PRReviewThread.threads(from: try PRReviewComment.parseGitHub(output))
        #expect(threads.count == 1)
        #expect(threads[0].replies.map(\.authorName) == ["bob"])
        #expect(threads[0].context == [" let a = 1", "-let b = 2", "+let bee = 2", "+let c = 3"])
    }

    @Test func orphanedReplyStartsItsOwnThread() {
        let reply = PRReviewComment(id: 3, replyTo: 99, authorName: "a", body: "", path: "x", line: 1, diffHunk: "", createdDate: Date())
        #expect(PRReviewThread.threads(from: [reply]).map(\.id) == [3])
    }

    @Test func postingClearsTheDraftAndReloadsThreads() async {
        let viewModel = PullRequestsViewModel(repository: MockGitRepository())
        await viewModel.refresh()
        #expect(viewModel.reviewThreads.count == 1)
        viewModel.setCommentDraft("   ")
        #expect(!viewModel.canPostComment)
        viewModel.setCommentDraft("Looks good")
        #expect(viewModel.canPostComment)
        await viewModel.postComment()
        #expect(viewModel.commentDraft.isEmpty)
        #expect(viewModel.commentError == nil)
        #expect(!viewModel.isPostingComment)
    }
}
