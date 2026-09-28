// Domain/Hosting/AzureDevOpsPullRequestHost.swift
// Grove
//
// Azure DevOps pull requests over its REST API (7.1), signed in with a personal access token.

import Foundation

nonisolated struct AzureDevOpsPullRequestHost: PullRequestHost {
    let location: RemoteLocation
    let client: RESTClient
    var kind: HostingServiceKind { .azureDevOps }

    private static let version = "api-version=7.1"

    private var repository: String {
        let project = location.project?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        let name = location.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? location.name
        return "https://dev.azure.com/\(location.owner)/\(project)/_apis/git/repositories/\(name)"
    }

    private func url(_ path: String, query: String = "") throws -> URL {
        let separator = query.isEmpty ? "" : "&"
        guard let url = URL(string: "\(repository)\(path)?\(query)\(separator)\(Self.version)") else {
            throw HostingError.unsupported("Bad Azure DevOps URL: \(path)")
        }
        return url
    }

    private func values(_ path: String, query: String = "") async throws -> [HostingJSON.Object] {
        HostingJSON.object(try await client.get(try url(path, query: query)))?["value"] as? [HostingJSON.Object] ?? []
    }

    func pullRequests() async throws -> [PullRequestInfo] {
        try await values("/pullrequests", query: "searchCriteria.status=all&$top=100").compactMap(AzureDevOpsParser.pullRequest)
    }

    func branchPullRequests() async throws -> [BranchPullRequest] {
        async let open = values("/pullrequests", query: "searchCriteria.status=active&$top=200")
        async let merged = values("/pullrequests", query: "searchCriteria.status=completed&$top=100")
        return HostingJSON.branchRows((try await open + merged).compactMap(AzureDevOpsParser.pullRequest)) { webPage($0) }
    }

    func pullRequest(number: Int) async throws -> PullRequestInfo {
        guard let pr = AzureDevOpsParser.pullRequest(try await detail(number)) else {
            throw HostingError.unsupported("Azure DevOps returned no pull request \(number).")
        }
        return pr
    }

    private func detail(_ number: Int) async throws -> HostingJSON.Object {
        HostingJSON.object(try await client.get(try url("/pullrequests/\(number)"))) ?? [:]
    }

    func comments(number: Int) async throws -> [PRComment] {
        AzureDevOpsParser.threads(try await values("/pullRequests/\(number)/threads")).comments
    }

    func reviewComments(number: Int) async throws -> [PRReviewComment] {
        AzureDevOpsParser.threads(try await values("/pullRequests/\(number)/threads")).lineComments
    }

    func commits(number: Int) async throws -> [CommitInfo] {
        try await values("/pullRequests/\(number)/commits").compactMap(AzureDevOpsParser.commit)
    }

    /// Azure DevOps has no unified-diff endpoint; the branches are diffed locally.
    func diff(number: Int) async throws -> String? { nil }

    /// Completing needs the source commit the merge is based on, so the detail is read first.
    func merge(number: Int) async throws {
        let current = try await detail(number)
        guard let commit = (current["lastMergeSourceCommit"] as? HostingJSON.Object)?["commitId"] as? String else {
            throw HostingError.unsupported("Azure DevOps didn't report the pull request's source commit.")
        }
        _ = try await client.send("PATCH", try url("/pullrequests/\(number)"),
                                  json: ["status": "completed", "lastMergeSourceCommit": ["commitId": commit]])
    }

    /// Closing without merging is "abandoned" in Azure DevOps.
    func close(number: Int) async throws {
        _ = try await client.send("PATCH", try url("/pullrequests/\(number)"), json: ["status": "abandoned"])
    }

    func updateBase(number: Int, base: String) async throws {
        _ = try await client.send("PATCH", try url("/pullrequests/\(number)"), json: ["targetRefName": "refs/heads/\(base)"])
    }

    func comment(number: Int, body: String) async throws {
        _ = try await client.send("POST", try url("/pullRequests/\(number)/threads"),
                                  json: ["comments": [["parentCommentId": 0, "content": body, "commentType": 1]], "status": 1])
    }

    func create(_ draft: PullRequestDraft) async throws -> String {
        let data = try await client.send("POST", try url("/pullrequests"), json: AzureDevOpsParser.createBody(draft))
        guard let id = HostingJSON.object(data)?["pullRequestId"] as? Int else { return "" }
        return webPage(id)
    }

    func webURL(number: Int) async throws -> URL? { URL(string: webPage(number)) }

    private func webPage(_ number: Int) -> String {
        let project = location.project?.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
        return "https://dev.azure.com/\(location.owner)/\(project)/_git/\(location.name)/pullrequest/\(number)"
    }

}

nonisolated enum AzureDevOpsParser {

    static func pullRequest(_ raw: HostingJSON.Object) -> PullRequestInfo? {
        guard let id = raw["pullRequestId"] as? Int, let title = raw["title"] as? String else { return nil }
        let author = raw["createdBy"] as? HostingJSON.Object
        let state: PRState = switch raw["status"] as? String {
        case "completed": .merged
        case "abandoned": .closed
        default: .open
        }
        let created = HostingJSON.date(raw["creationDate"])
        let labels = (raw["labels"] as? [HostingJSON.Object] ?? []).compactMap { $0["name"] as? String }
            .map { PRLabel(id: $0, name: $0, color: "") }
        let reviewers = (raw["reviewers"] as? [HostingJSON.Object] ?? []).compactMap { $0["displayName"] as? String }
        return PullRequestInfo(
            id: id, title: title, body: (raw["description"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            authorName: author?["displayName"] as? String ?? "Unknown", authorAvatarURL: author?["imageUrl"] as? String,
            state: state,
            sourceBranch: (raw["sourceRefName"] as? String ?? "").withoutHeadsPrefix,
            targetBranch: (raw["targetRefName"] as? String ?? "").withoutHeadsPrefix,
            // There's no "updated" date; closing is the last change the list reports.
            createdDate: created, updatedDate: (raw["closedDate"] as? String).flatMap(GitDate.parse) ?? created,
            isDraft: raw["isDraft"] as? Bool ?? false, labels: labels, reviewers: reviewers, checksStatus: .none,
            headSHA: (raw["lastMergeSourceCommit"] as? HostingJSON.Object)?["commitId"] as? String
        )
    }

    /// Threads anchored to a file are line comments; system threads (votes, pushes) are skipped.
    static func threads(_ values: [HostingJSON.Object]) -> (comments: [PRComment], lineComments: [PRReviewComment]) {
        var comments: [PRComment] = []
        var lineComments: [PRReviewComment] = []
        for thread in values where thread["isDeleted"] as? Bool != true {
            let context = thread["threadContext"] as? HostingJSON.Object
            let path = (context?["filePath"] as? String).map { $0.hasPrefix("/") ? String($0.dropFirst()) : $0 }
            let line = ((context?["rightFileStart"] ?? context?["leftFileStart"]) as? HostingJSON.Object)?["line"] as? Int
            let entries = (thread["comments"] as? [HostingJSON.Object] ?? []).filter { $0["commentType"] as? String != "system" }
            let rootID = entries.first?["id"] as? Int
            for raw in entries {
                guard let commentID = raw["id"] as? Int, let threadID = thread["id"] as? Int else { continue }
                let author = (raw["author"] as? HostingJSON.Object)?["displayName"] as? String ?? "Unknown"
                let body = raw["content"] as? String ?? ""
                let date = HostingJSON.date(raw["publishedDate"])
                // Comment ids restart per thread, so the thread id keeps them unique.
                let id = threadID * 1000 + commentID
                if let path {
                    lineComments.append(PRReviewComment(
                        id: id, replyTo: commentID == rootID ? nil : threadID * 1000 + (rootID ?? 0), authorName: author, body: body,
                        path: path, line: line, diffHunk: "", createdDate: date))
                } else {
                    comments.append(PRComment(id: "thread-\(id)", authorName: author, authorAvatarURL: nil, body: body,
                                              createdDate: date, isReview: false))
                }
            }
        }
        return (comments.sorted { $0.createdDate < $1.createdDate }, lineComments.sorted { $0.createdDate < $1.createdDate })
    }

    static func commit(_ raw: HostingJSON.Object) -> CommitInfo? {
        guard let id = raw["commitId"] as? String else { return nil }
        let author = raw["author"] as? HostingJSON.Object
        let committer = raw["committer"] as? HostingJSON.Object
        return HostingJSON.commit(id: id, message: raw["comment"] as? String ?? "", authorName: author?["name"] as? String ?? "",
                                  authorEmail: author?["email"] as? String ?? "", authored: HostingJSON.date(author?["date"]),
                                  committed: HostingJSON.date(committer?["date"]))
    }

    /// Reviewers need identity ids Grove doesn't have, so they're left for the web page.
    static func createBody(_ draft: PullRequestDraft) -> [String: Any] {
        ["sourceRefName": "refs/heads/\(draft.head)", "targetRefName": "refs/heads/\(draft.base)",
         "title": draft.title, "description": draft.body, "isDraft": draft.isDraft]
    }
}
