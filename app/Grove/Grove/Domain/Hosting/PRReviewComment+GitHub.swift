// Domain/Hosting/PRReviewComment+GitHub.swift
// Grove
//
// GitHub's line comments, read into GroveKit's review comment model.

import Foundation
import GroveKit

extension PRReviewComment {
    /// One entry of GitHub's `GET /repos/…/pulls/N/comments`.
    static func gitHub(_ raw: HostingJSON.Object) -> PRReviewComment? {
        guard let id = raw["id"] as? Int else { return nil }
        return PRReviewComment(
            id: id, replyTo: raw["in_reply_to_id"] as? Int,
            authorName: (raw["user"] as? HostingJSON.Object)?["login"] as? String ?? "ghost",
            body: raw["body"] as? String ?? "", path: raw["path"] as? String ?? "",
            line: raw["line"] as? Int ?? raw["original_line"] as? Int, diffHunk: raw["diff_hunk"] as? String ?? "",
            createdDate: HostingJSON.date(raw["created_at"])
        )
    }

    /// A page (or several, or one object per line) of GitHub line comments, oldest first.
    static func parseGitHub(_ output: String) throws -> [PRReviewComment] {
        HostingJSON.objects(output).compactMap(gitHub).sorted { $0.createdDate < $1.createdDate }
    }
}
