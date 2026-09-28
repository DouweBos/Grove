// Domain/Hosting/GitLabPullRequestHost.swift
// Grove
//
// GitLab merge requests: reads through `glab api` (GitLab's REST shapes), writes through glab where it has a command.

import Foundation

nonisolated struct GitLabPullRequestHost: PullRequestHost {
    let directory: URL
    let location: RemoteLocation
    var kind: HostingServiceKind { .gitlab }

    private var project: String { GitLabCLI.projectPath(location) }

    private func api(_ path: String, method: String = "GET", fields: [String: String] = [:], paginate: Bool = false) async throws -> String {
        try await GitLabCLI.api(path, host: location.host, method: method, fields: fields, paginate: paginate)
    }

    func pullRequests() async throws -> [PullRequestInfo] {
        let output = try await api("\(project)/merge_requests?state=all&order_by=updated_at&per_page=100")
        return HostingJSON.objects(output).compactMap(GitLabParser.mergeRequest)
    }

    func openPullRequests() async throws -> [String: OpenPullRequest] {
        let output = try await api("\(project)/merge_requests?state=opened&per_page=100", paginate: true)
        let requests = HostingJSON.objects(output)
        let urls = Dictionary(requests.compactMap { raw in (raw["iid"] as? Int).map { ($0, raw["web_url"] as? String ?? "") } },
                              uniquingKeysWith: { first, _ in first })
        return HostingJSON.openIndex(requests.compactMap(GitLabParser.mergeRequest)) { urls[$0] ?? "" }
    }

    func pullRequest(number: Int) async throws -> PullRequestInfo {
        guard let request = GitLabParser.mergeRequest(HostingJSON.objects(try await api("\(project)/merge_requests/\(number)")).first ?? [:])
        else { throw HostingError.unsupported("GitLab returned no merge request !\(number).") }
        return request
    }

    func comments(number: Int) async throws -> [PRComment] {
        GitLabParser.discussions(HostingJSON.objects(try await discussions(number))).comments
    }

    func reviewComments(number: Int) async throws -> [PRReviewComment] {
        GitLabParser.discussions(HostingJSON.objects(try await discussions(number))).lineComments
    }

    private func discussions(_ number: Int) async throws -> String {
        try await api("\(project)/merge_requests/\(number)/discussions?per_page=100", paginate: true)
    }

    func commits(number: Int) async throws -> [CommitInfo] {
        HostingJSON.objects(try await api("\(project)/merge_requests/\(number)/commits?per_page=100", paginate: true))
            .compactMap(GitLabParser.commit)
    }

    func diff(number: Int) async throws -> String? {
        try await GitLabCLI.run(["mr", "diff", "\(number)", "--raw"], in: directory)
    }

    func merge(number: Int) async throws {
        _ = try await api("\(project)/merge_requests/\(number)/merge", method: "PUT")
    }

    func close(number: Int) async throws {
        _ = try await api("\(project)/merge_requests/\(number)", method: "PUT", fields: ["state_event": "close"])
    }

    func comment(number: Int, body: String) async throws {
        _ = try await api("\(project)/merge_requests/\(number)/notes", method: "POST", fields: ["body": body])
    }

    func create(_ draft: PullRequestDraft) async throws -> String {
        let output = try await GitLabCLI.run(GitLabParser.createArguments(draft), in: directory)
        return GitLabParser.mergeRequestURL(in: output) ?? ""
    }

    func webURL(number: Int) async throws -> URL? {
        URL(string: "https://\(location.host)/\(location.fullName)/-/merge_requests/\(number)")
    }

    func checkout(number: Int) async throws -> Bool {
        _ = try await GitLabCLI.run(["mr", "checkout", "\(number)"], in: directory)
        return true
    }
}

nonisolated enum GitLabParser {

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

    static func createArguments(_ draft: PullRequestDraft) -> [String] {
        var arguments = ["mr", "create", "--source-branch", draft.head, "--target-branch", draft.base,
                         "--title", draft.title, "--description", draft.body, "--yes", "--no-editor"]
        if draft.isDraft { arguments.append("--draft") }
        if !draft.reviewers.isEmpty { arguments += ["--reviewer", draft.reviewers.joined(separator: ",")] }
        return arguments
    }

    /// glab prints progress and then the merge request's URL.
    static func mergeRequestURL(in output: String) -> String? {
        output.split(whereSeparator: \.isWhitespace).map(String.init)
            .last { $0.hasPrefix("http") && $0.contains("/merge_requests/") }
    }
}
