// Domain/Hosting/GitLabPullRequestHost.swift
// Grove
//
// GitLab and self-hosted GitLab merge requests over the v4 REST API.

import Foundation

nonisolated struct GitLabPullRequestHost: PullRequestHost {
    let location: RemoteLocation
    let client: RESTClient
    var kind: HostingServiceKind { .gitlab }

    private var project: String { "\(client.credentials.account.apiBase)/\(GitLabParser.projectPath(location))" }

    private func url(_ path: String) throws -> URL {
        guard let url = URL(string: project + path) else { throw HostingError.unsupported("Bad GitLab URL: \(path)") }
        return url
    }

    func pullRequests() async throws -> [PullRequestInfo] {
        HostingJSON.objects(String(bytes: try await client.get(try url("/merge_requests?state=all&order_by=updated_at&per_page=100")),
                                   encoding: .utf8) ?? "")
            .compactMap(GitLabParser.mergeRequest)
    }

    func openPullRequests() async throws -> [String: OpenPullRequest] {
        let requests = try await client.getPages(try url("/merge_requests?state=opened&per_page=100"))
        let urls = Dictionary(requests.compactMap { raw in (raw["iid"] as? Int).map { ($0, raw["web_url"] as? String ?? "") } },
                              uniquingKeysWith: { first, _ in first })
        return HostingJSON.openIndex(requests.compactMap(GitLabParser.mergeRequest)) { urls[$0] ?? "" }
    }

    func pullRequest(number: Int) async throws -> PullRequestInfo {
        guard let request = HostingJSON.object(try await client.get(try url("/merge_requests/\(number)"))).flatMap(GitLabParser.mergeRequest)
        else { throw HostingError.unsupported("GitLab returned no merge request !\(number).") }
        return request
    }

    func comments(number: Int) async throws -> [PRComment] {
        GitLabParser.discussions(try await discussions(number)).comments
    }

    func reviewComments(number: Int) async throws -> [PRReviewComment] {
        GitLabParser.discussions(try await discussions(number)).lineComments
    }

    private func discussions(_ number: Int) async throws -> [HostingJSON.Object] {
        try await client.getPages(try url("/merge_requests/\(number)/discussions?per_page=100"))
    }

    func commits(number: Int) async throws -> [CommitInfo] {
        try await client.getPages(try url("/merge_requests/\(number)/commits?per_page=100")).compactMap(GitLabParser.commit)
    }

    func diff(number: Int) async throws -> String? {
        GitLabParser.unifiedDiff(try await client.getPages(try url("/merge_requests/\(number)/diffs?per_page=100")))
    }

    func merge(number: Int) async throws {
        try await client.send("PUT", try url("/merge_requests/\(number)/merge"), json: [:])
    }

    func close(number: Int) async throws {
        try await client.send("PUT", try url("/merge_requests/\(number)"), json: ["state_event": "close"])
    }

    func comment(number: Int, body: String) async throws {
        try await client.send("POST", try url("/merge_requests/\(number)/notes"), json: ["body": body])
    }

    /// Reviewers are looked up by username first, since GitLab takes their ids.
    func create(_ draft: PullRequestDraft) async throws -> String {
        var ids: [Int] = []
        for username in draft.reviewers {
            guard let lookup = URL(string: "\(client.credentials.account.apiBase)/users?username=\(username)") else { continue }
            if let id = HostingJSON.objects(String(bytes: try await client.get(lookup), encoding: .utf8) ?? "").first?["id"] as? Int {
                ids.append(id)
            }
        }
        let data = try await client.send("POST", try url("/merge_requests"), json: GitLabParser.createBody(draft, reviewerIDs: ids))
        return HostingJSON.object(data)?["web_url"] as? String ?? ""
    }

    func webURL(number: Int) async throws -> URL? {
        URL(string: "https://\(location.host)/\(location.fullName)/-/merge_requests/\(number)")
    }

    func headRef(number: Int) -> String? { "refs/merge-requests/\(number)/head" }
}

nonisolated enum GitLabParser {

    /// GitLab addresses a project by its URL-encoded full path.
    static func projectPath(_ location: RemoteLocation) -> String {
        "projects/" + encoded(location.fullName)
    }

    static func encoded(_ path: String) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return path.addingPercentEncoding(withAllowedCharacters: unreserved) ?? path
    }

    /// One entry of `GET projects/:id/merge_requests`.
    static func mergeRequest(_ raw: HostingJSON.Object) -> PullRequestInfo? {
        guard let iid = raw["iid"] as? Int, let title = raw["title"] as? String else { return nil }
        let author = raw["author"] as? HostingJSON.Object
        let state: PRState = switch raw["state"] as? String {
        case "merged": .merged
        case "closed", "locked": .closed
        default: .open
        }
        let pipeline = (raw["head_pipeline"] as? HostingJSON.Object)?["status"] as? String
        let checks: PRChecksStatus = switch pipeline {
        case "success": .passing
        case "failed", "canceled": .failing
        case "running", "pending", "created", "preparing", "waiting_for_resource": .pending
        default: .none
        }
        let labels = (raw["labels"] as? [String] ?? []).map { PRLabel(id: $0, name: $0, color: "") }
        let reviewers = (raw["reviewers"] as? [HostingJSON.Object] ?? []).compactMap { $0["username"] as? String }
        let created = HostingJSON.date(raw["created_at"])
        return PullRequestInfo(
            id: iid, title: title, body: (raw["description"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            authorName: author?["username"] as? String ?? author?["name"] as? String ?? "Unknown",
            authorAvatarURL: author?["avatar_url"] as? String, state: state,
            sourceBranch: raw["source_branch"] as? String ?? "", targetBranch: raw["target_branch"] as? String ?? "",
            createdDate: created, updatedDate: (raw["updated_at"] as? String).flatMap(GitDate.parse) ?? created,
            isDraft: raw["draft"] as? Bool ?? raw["work_in_progress"] as? Bool ?? false,
            labels: labels, reviewers: reviewers, checksStatus: checks
        )
    }

    /// `GET .../discussions`: plain notes become the conversation, diff notes line comments. System notes are skipped.
    static func discussions(_ threads: [HostingJSON.Object]) -> (comments: [PRComment], lineComments: [PRReviewComment]) {
        var comments: [PRComment] = []
        var lineComments: [PRReviewComment] = []
        for thread in threads {
            let notes = (thread["notes"] as? [HostingJSON.Object] ?? []).filter { $0["system"] as? Bool != true }
            let rootID = notes.first?["id"] as? Int
            for note in notes {
                guard let id = note["id"] as? Int else { continue }
                let author = (note["author"] as? HostingJSON.Object)?["username"] as? String ?? "Unknown"
                let body = note["body"] as? String ?? ""
                let date = HostingJSON.date(note["created_at"])
                if let position = note["position"] as? HostingJSON.Object {
                    lineComments.append(PRReviewComment(
                        id: id, replyTo: id == rootID ? nil : rootID, authorName: author, body: body,
                        path: position["new_path"] as? String ?? position["old_path"] as? String ?? "",
                        line: position["new_line"] as? Int ?? position["old_line"] as? Int, diffHunk: "", createdDate: date))
                } else {
                    comments.append(PRComment(id: "note-\(id)", authorName: author, authorAvatarURL: nil, body: body,
                                              createdDate: date, isReview: false))
                }
            }
        }
        return (comments.sorted { $0.createdDate < $1.createdDate }, lineComments.sorted { $0.createdDate < $1.createdDate })
    }

    /// One entry of `GET .../merge_requests/:iid/commits`, newest first like GitLab lists them.
    static func commit(_ raw: HostingJSON.Object) -> CommitInfo? {
        guard let id = raw["id"] as? String else { return nil }
        return HostingJSON.commit(id: id, message: raw["message"] as? String ?? raw["title"] as? String ?? "",
                                  authorName: raw["author_name"] as? String ?? "", authorEmail: raw["author_email"] as? String ?? "",
                                  authored: HostingJSON.date(raw["authored_date"]), committed: HostingJSON.date(raw["committed_date"]))
    }

    /// GitLab returns each file's hunks without git's headers; they're added back so the diff parser reads them.
    static func unifiedDiff(_ files: [HostingJSON.Object]) -> String {
        files.map { file in
            let old = file["old_path"] as? String ?? ""
            let new = file["new_path"] as? String ?? old
            var header = "diff --git a/\(old) b/\(new)\n"
            if file["new_file"] as? Bool == true { header += "new file mode 100644\n" }
            if file["deleted_file"] as? Bool == true { header += "deleted file mode 100644\n" }
            if file["renamed_file"] as? Bool == true { header += "rename from \(old)\nrename to \(new)\n" }
            let from = file["new_file"] as? Bool == true ? "/dev/null" : "a/\(old)"
            let to = file["deleted_file"] as? Bool == true ? "/dev/null" : "b/\(new)"
            let hunks = file["diff"] as? String ?? ""
            return header + (hunks.isEmpty ? "" : "--- \(from)\n+++ \(to)\n" + hunks + (hunks.hasSuffix("\n") ? "" : "\n"))
        }
        .joined()
    }

    /// GitLab marks drafts by a "Draft:" title prefix.
    static func createBody(_ draft: PullRequestDraft, reviewerIDs: [Int]) -> [String: Any] {
        var body: [String: Any] = ["source_branch": draft.head, "target_branch": draft.base,
                                   "title": draft.isDraft ? "Draft: \(draft.title)" : draft.title, "description": draft.body]
        if !reviewerIDs.isEmpty { body["reviewer_ids"] = reviewerIDs }
        return body
    }
}
