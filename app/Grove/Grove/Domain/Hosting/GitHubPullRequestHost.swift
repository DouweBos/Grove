// Domain/Hosting/GitHubPullRequestHost.swift
// Grove
//
// GitHub and GitHub Enterprise pull requests: GraphQL for lists (checks and reviewers in one call), REST for the rest.

import Foundation

nonisolated struct GitHubPullRequestHost: PullRequestHost {
    let location: RemoteLocation
    let client: RESTClient
    var kind: HostingServiceKind { .github }

    private var api: String { client.credentials.account.apiBase }
    private var repository: String { "\(api)/repos/\(location.owner)/\(location.name)" }

    private func url(_ path: String) throws -> URL {
        guard let url = URL(string: repository + path) else { throw HostingError.unsupported("Bad GitHub URL: \(path)") }
        return url
    }

    /// `declarations` lists only the variables `selection` uses; GitHub rejects unused ones.
    private func query(_ declarations: String, _ selection: String, _ variables: [String: Any]) async throws -> HostingJSON.Object {
        guard let endpoint = client.credentials.account.graphQLURL else { throw HostingError.unsupported("Bad GitHub host.") }
        let document = "query($owner: String!, $name: String!\(declarations)) "
            + "{ repository(owner: $owner, name: $name) { \(selection) } }"
        let data = try await client.graphQL(endpoint, query: document,
                                            variables: ["owner": location.owner, "name": location.name].merging(variables) { $1 })
        guard let repository = data["repository"] as? HostingJSON.Object else {
            throw HostingError.unsupported("GitHub can't see \(location.fullName) with this account.")
        }
        return repository
    }

    func pullRequests() async throws -> [PullRequestInfo] {
        let repository = try await query(
            ", $count: Int!", "pullRequests(first: $count, orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { \(GitHubParser.fields) } }",
            ["count": 100])
        return GitHubParser.nodes(repository["pullRequests"]).compactMap(GitHubParser.pullRequest)
    }

    /// Only what branch rows and stacks show, so it stays a small response even for busy repositories.
    /// Open and merged are separate lists so recent merges can't crowd out older open pull requests.
    func branchPullRequests() async throws -> [BranchPullRequest] {
        let row = "nodes { number title headRefName baseRefName headRefOid isDraft url "
            + "commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } }"
        let repository = try await query(
            ", $count: Int!",
            "open: pullRequests(first: $count, states: [OPEN], orderBy: {field: CREATED_AT, direction: DESC}) { \(row) } "
                + "merged: pullRequests(first: $count, states: [MERGED], orderBy: {field: UPDATED_AT, direction: DESC}) { \(row) }",
            ["count": 100])
        return GitHubParser.nodes(repository["open"]).compactMap { GitHubParser.branchRow($0, isMerged: false) }
            + GitHubParser.nodes(repository["merged"]).compactMap { GitHubParser.branchRow($0, isMerged: true) }
    }

    func pullRequest(number: Int) async throws -> PullRequestInfo {
        let repository = try await query(", $number: Int!", "pullRequest(number: $number) { \(GitHubParser.fields) }", ["number": number])
        guard let pr = (repository["pullRequest"] as? HostingJSON.Object).flatMap(GitHubParser.pullRequest) else {
            throw HostingError.unsupported("GitHub returned no pull request #\(number).")
        }
        return pr
    }

    /// The conversation: issue comments plus reviews that say something.
    func comments(number: Int) async throws -> [PRComment] {
        async let issueComments = client.getPages(try url("/issues/\(number)/comments?per_page=100"))
        async let reviews = client.getPages(try url("/pulls/\(number)/reviews?per_page=100"))
        return GitHubParser.conversation(comments: try await issueComments, reviews: try await reviews)
    }

    func reviewComments(number: Int) async throws -> [PRReviewComment] {
        try await client.getPages(try url("/pulls/\(number)/comments?per_page=100")).compactMap(PRReviewComment.gitHub)
            .sorted { $0.createdDate < $1.createdDate }
    }

    func commits(number: Int) async throws -> [CommitInfo] {
        // GitHub lists oldest first; Grove lists newest first.
        try await client.getPages(try url("/pulls/\(number)/commits?per_page=100")).compactMap(GitHubParser.commit).reversed()
    }

    func diff(number: Int) async throws -> String? {
        String(bytes: try await client.get(try url("/pulls/\(number)"), accept: "application/vnd.github.diff"), encoding: .utf8)
    }

    func merge(number: Int) async throws {
        try await client.send("PUT", try url("/pulls/\(number)/merge"), json: ["merge_method": "merge"])
    }

    func close(number: Int) async throws {
        try await client.send("PATCH", try url("/pulls/\(number)"), json: ["state": "closed"])
    }

    func updateBase(number: Int, base: String) async throws {
        try await client.send("PATCH", try url("/pulls/\(number)"), json: ["base": base])
    }

    func comment(number: Int, body: String) async throws {
        try await client.send("POST", try url("/issues/\(number)/comments"), json: ["body": body])
    }

    /// Opens the pull request, then asks the reviewers, which GitHub takes as a separate request.
    func create(_ draft: PullRequestDraft) async throws -> String {
        let data = try await client.send("POST", try url("/pulls"), json: GitHubParser.createBody(draft))
        let created = HostingJSON.object(data) ?? [:]
        if !draft.reviewers.isEmpty, let number = created["number"] as? Int {
            try await client.send("POST", try url("/pulls/\(number)/requested_reviewers"), json: ["reviewers": draft.reviewers])
        }
        return created["html_url"] as? String ?? ""
    }

    func webURL(number: Int) async throws -> URL? {
        URL(string: "https://\(location.host)/\(location.fullName)/pull/\(number)")
    }

    func headRef(number: Int) -> String? { "refs/pull/\(number)/head" }
}

nonisolated enum GitHubParser {

    static let fields = "number title body url state isDraft headRefName baseRefName headRefOid createdAt updatedAt "
        + "author { login avatarUrl } labels(first: 20) { nodes { name color } } "
        + "reviewRequests(first: 20) { nodes { requestedReviewer { ... on User { login } ... on Team { name } ... on Bot { login } } } } "
        + "commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }"

    static func nodes(_ connection: Any?) -> [HostingJSON.Object] {
        (connection as? HostingJSON.Object)?["nodes"] as? [HostingJSON.Object] ?? []
    }

    static func pullRequest(_ node: HostingJSON.Object) -> PullRequestInfo? {
        guard let number = node["number"] as? Int, let title = node["title"] as? String else { return nil }
        let author = node["author"] as? HostingJSON.Object
        let state: PRState = switch node["state"] as? String {
        case "MERGED": .merged
        case "CLOSED": .closed
        default: .open
        }
        let checks = checksStatus(node)
        let labels = nodes(node["labels"]).compactMap { label -> PRLabel? in
            guard let name = label["name"] as? String else { return nil }
            return PRLabel(id: name, name: name, color: label["color"] as? String ?? "")
        }
        let reviewers = nodes(node["reviewRequests"]).compactMap { request -> String? in
            let reviewer = request["requestedReviewer"] as? HostingJSON.Object
            return reviewer?["login"] as? String ?? reviewer?["name"] as? String
        }
        let created = HostingJSON.date(node["createdAt"])
        return PullRequestInfo(
            id: number, title: title, body: (node["body"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            authorName: author?["login"] as? String ?? "ghost", authorAvatarURL: author?["avatarUrl"] as? String, state: state,
            sourceBranch: node["headRefName"] as? String ?? "", targetBranch: node["baseRefName"] as? String ?? "",
            createdDate: created, updatedDate: (node["updatedAt"] as? String).flatMap(GitDate.parse) ?? created,
            isDraft: node["isDraft"] as? Bool ?? false, labels: labels, reviewers: reviewers, checksStatus: checks,
            headSHA: node["headRefOid"] as? String
        )
    }

    static func branchRow(_ node: HostingJSON.Object, isMerged: Bool) -> BranchPullRequest? {
        guard let number = node["number"] as? Int, let head = node["headRefName"] as? String else { return nil }
        return BranchPullRequest(number: number, title: node["title"] as? String ?? "", headBranch: head,
                                 isDraft: node["isDraft"] as? Bool ?? false, url: node["url"] as? String ?? "",
                                 baseBranch: node["baseRefName"] as? String ?? "", isMerged: isMerged,
                                 headSHA: node["headRefOid"] as? String, checks: checksStatus(node))
    }

    private static func checksStatus(_ node: HostingJSON.Object) -> PRChecksStatus {
        let rollup = ((nodes(node["commits"]).first?["commit"] as? HostingJSON.Object)?["statusCheckRollup"] as? HostingJSON.Object)?["state"]
        return switch rollup as? String {
        case "SUCCESS": .passing
        case "FAILURE", "ERROR": .failing
        case "PENDING", "EXPECTED": .pending
        default: .none
        }
    }

    static func conversation(comments: [HostingJSON.Object], reviews: [HostingJSON.Object]) -> [PRComment] {
        let plain = comments.compactMap { raw -> PRComment? in
            guard let id = raw["id"] as? Int else { return nil }
            return PRComment(id: "comment-\(id)", authorName: login(raw), authorAvatarURL: avatar(raw),
                             body: raw["body"] as? String ?? "", createdDate: HostingJSON.date(raw["created_at"]), isReview: false)
        }
        let reviewed = reviews.compactMap { raw -> PRComment? in
            guard let id = raw["id"] as? Int, let body = raw["body"] as? String, !body.isEmpty else { return nil }
            return PRComment(id: "review-\(id)", authorName: login(raw), authorAvatarURL: avatar(raw), body: body,
                             createdDate: HostingJSON.date(raw["submitted_at"]), isReview: true)
        }
        return (plain + reviewed).sorted { $0.createdDate < $1.createdDate }
    }

    private static func login(_ raw: HostingJSON.Object) -> String {
        (raw["user"] as? HostingJSON.Object)?["login"] as? String ?? "ghost"
    }

    private static func avatar(_ raw: HostingJSON.Object) -> String? {
        (raw["user"] as? HostingJSON.Object)?["avatar_url"] as? String
    }

    /// One entry of `GET /repos/…/pulls/N/commits`.
    static func commit(_ raw: HostingJSON.Object) -> CommitInfo? {
        guard let sha = raw["sha"] as? String, let commit = raw["commit"] as? HostingJSON.Object else { return nil }
        let author = commit["author"] as? HostingJSON.Object
        let committer = commit["committer"] as? HostingJSON.Object
        return HostingJSON.commit(id: sha, message: commit["message"] as? String ?? "", authorName: author?["name"] as? String ?? "",
                                  authorEmail: author?["email"] as? String ?? "", authored: HostingJSON.date(author?["date"]),
                                  committed: HostingJSON.date(committer?["date"]))
    }

    static func createBody(_ draft: PullRequestDraft) -> [String: Any] {
        ["title": draft.title, "head": draft.head, "base": draft.base, "body": draft.body, "draft": draft.isDraft]
    }

    /// One repository from `GET /user/repos`, `/orgs/{org}/repos` or `POST …/repos`.
    static func repository(_ raw: HostingJSON.Object, host: String) -> RemoteRepository? {
        guard let fullName = raw["full_name"] as? String, let name = raw["name"] as? String else { return nil }
        return RemoteRepository(
            nameWithOwner: fullName, name: name, owner: (raw["owner"] as? HostingJSON.Object)?["login"] as? String ?? "",
            description: (raw["description"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            isPrivate: raw["private"] as? Bool ?? false, isFork: raw["fork"] as? Bool ?? false,
            isArchived: raw["archived"] as? Bool ?? false,
            updatedAt: ((raw["pushed_at"] ?? raw["updated_at"]) as? String).flatMap(GitDate.parse),
            webURL: raw["html_url"] as? String ?? "https://\(host)/\(fullName)",
            sshURL: raw["ssh_url"] as? String ?? "git@\(host):\(fullName).git",
            defaultBranch: raw["default_branch"] as? String, language: raw["language"] as? String,
            service: .github, cloneURL: raw["clone_url"] as? String
        )
    }
}
