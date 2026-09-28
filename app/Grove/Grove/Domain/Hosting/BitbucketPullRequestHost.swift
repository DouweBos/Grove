// Domain/Hosting/BitbucketPullRequestHost.swift
// Grove
//
// Bitbucket Cloud pull requests over its 2.0 REST API, signed in with an app password or API token.

import Foundation

nonisolated struct BitbucketPullRequestHost: PullRequestHost {
    let location: RemoteLocation
    let client: RESTClient
    var kind: HostingServiceKind { .bitbucket }

    static let api = "https://api.bitbucket.org/2.0"

    private var base: String { "\(Self.api)/repositories/\(location.owner)/\(location.name)/pullrequests" }

    private func url(_ path: String) throws -> URL {
        guard let url = URL(string: base + path) else { throw HostingError.unsupported("Bad Bitbucket URL: \(path)") }
        return url
    }

    private func values(_ path: String) async throws -> [HostingJSON.Object] {
        HostingJSON.object(try await client.get(try url(path)))?["values"] as? [HostingJSON.Object] ?? []
    }

    func pullRequests() async throws -> [PullRequestInfo] {
        try await values("?state=OPEN&state=MERGED&state=DECLINED&state=SUPERSEDED&sort=-updated_on&pagelen=50")
            .compactMap(BitbucketParser.pullRequest)
    }

    func branchPullRequests() async throws -> [BranchPullRequest] {
        async let open = values("?state=OPEN&pagelen=50")
        async let merged = values("?state=MERGED&sort=-updated_on&pagelen=50")
        return HostingJSON.branchRows((try await open + merged).compactMap(BitbucketParser.pullRequest)) {
            "https://bitbucket.org/\(location.fullName)/pull-requests/\($0)"
        }
    }

    func pullRequest(number: Int) async throws -> PullRequestInfo {
        guard let object = HostingJSON.object(try await client.get(try url("/\(number)"))),
              let pr = BitbucketParser.pullRequest(object) else { throw HostingError.unsupported("Bitbucket returned no pull request #\(number).") }
        return pr
    }

    func comments(number: Int) async throws -> [PRComment] {
        BitbucketParser.comments(try await values("/\(number)/comments?pagelen=100")).comments
    }

    func reviewComments(number: Int) async throws -> [PRReviewComment] {
        BitbucketParser.comments(try await values("/\(number)/comments?pagelen=100")).lineComments
    }

    func commits(number: Int) async throws -> [CommitInfo] {
        try await values("/\(number)/commits?pagelen=100").compactMap(BitbucketParser.commit)
    }

    func diff(number: Int) async throws -> String? {
        String(bytes: try await client.get(try url("/\(number)/diff"), accept: "text/plain"), encoding: .utf8)
    }

    func merge(number: Int) async throws {
        _ = try await client.send("POST", try url("/\(number)/merge"), json: ["merge_strategy": "merge_commit"])
    }

    /// Bitbucket calls closing without merging "decline".
    func close(number: Int) async throws {
        _ = try await client.send("POST", try url("/\(number)/decline"), json: nil)
    }

    func comment(number: Int, body: String) async throws {
        _ = try await client.send("POST", try url("/\(number)/comments"), json: ["content": ["raw": body]])
    }

    func create(_ draft: PullRequestDraft) async throws -> String {
        let data = try await client.send("POST", try url(""), json: BitbucketParser.createBody(draft))
        let links = HostingJSON.object(data)?["links"] as? HostingJSON.Object
        return (links?["html"] as? HostingJSON.Object)?["href"] as? String ?? ""
    }

    func webURL(number: Int) async throws -> URL? {
        URL(string: "https://bitbucket.org/\(location.fullName)/pull-requests/\(number)")
    }

}

nonisolated enum BitbucketParser {

    static func pullRequest(_ raw: HostingJSON.Object) -> PullRequestInfo? {
        guard let id = raw["id"] as? Int, let title = raw["title"] as? String else { return nil }
        let author = raw["author"] as? HostingJSON.Object
        let state: PRState = switch raw["state"] as? String {
        case "MERGED": .merged
        case "DECLINED", "SUPERSEDED": .closed
        default: .open
        }
        let created = HostingJSON.date(raw["created_on"])
        let reviewers = (raw["reviewers"] as? [HostingJSON.Object] ?? []).compactMap { $0["display_name"] as? String }
        let avatar = ((author?["links"] as? HostingJSON.Object)?["avatar"] as? HostingJSON.Object)?["href"] as? String
        return PullRequestInfo(
            id: id, title: title, body: (raw["description"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            authorName: author?["display_name"] as? String ?? author?["nickname"] as? String ?? "Unknown",
            authorAvatarURL: avatar, state: state,
            sourceBranch: branch(raw["source"]), targetBranch: branch(raw["destination"]),
            createdDate: created, updatedDate: (raw["updated_on"] as? String).flatMap(GitDate.parse) ?? created,
            isDraft: raw["draft"] as? Bool ?? false, labels: [], reviewers: reviewers, checksStatus: .none,
            headSHA: (((raw["source"] as? HostingJSON.Object)?["commit"] as? HostingJSON.Object)?["hash"] as? String)
        )
    }

    private static func branch(_ side: Any?) -> String {
        ((side as? HostingJSON.Object)?["branch"] as? HostingJSON.Object)?["name"] as? String ?? ""
    }

    /// Comments with an `inline` anchor are line comments; deleted ones are dropped.
    static func comments(_ values: [HostingJSON.Object]) -> (comments: [PRComment], lineComments: [PRReviewComment]) {
        var comments: [PRComment] = []
        var lineComments: [PRReviewComment] = []
        for raw in values where raw["deleted"] as? Bool != true {
            guard let id = raw["id"] as? Int else { continue }
            let author = (raw["user"] as? HostingJSON.Object)?["display_name"] as? String ?? "Unknown"
            let body = (raw["content"] as? HostingJSON.Object)?["raw"] as? String ?? ""
            let date = HostingJSON.date(raw["created_on"])
            if let inline = raw["inline"] as? HostingJSON.Object {
                lineComments.append(PRReviewComment(
                    id: id, replyTo: (raw["parent"] as? HostingJSON.Object)?["id"] as? Int, authorName: author, body: body,
                    path: inline["path"] as? String ?? "", line: inline["to"] as? Int ?? inline["from"] as? Int,
                    diffHunk: "", createdDate: date))
            } else {
                comments.append(PRComment(id: "comment-\(id)", authorName: author, authorAvatarURL: nil, body: body,
                                          createdDate: date, isReview: false))
            }
        }
        return (comments.sorted { $0.createdDate < $1.createdDate }, lineComments.sorted { $0.createdDate < $1.createdDate })
    }

    static func commit(_ raw: HostingJSON.Object) -> CommitInfo? {
        guard let hash = raw["hash"] as? String else { return nil }
        let author = raw["author"] as? HostingJSON.Object
        let (name, email) = HostingJSON.nameAndEmail(author?["raw"] as? String ?? "")
        let display = (author?["user"] as? HostingJSON.Object)?["display_name"] as? String
        return HostingJSON.commit(id: hash, message: raw["message"] as? String ?? "", authorName: display ?? name,
                                  authorEmail: email, authored: HostingJSON.date(raw["date"]))
    }

    /// Reviewers need account ids Grove doesn't have, so they're left for the web page.
    static func createBody(_ draft: PullRequestDraft) -> [String: Any] {
        ["title": draft.title, "description": draft.body, "draft": draft.isDraft,
         "source": ["branch": ["name": draft.head]], "destination": ["branch": ["name": draft.base]]]
    }
}
