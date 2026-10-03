// HostingAPITests.swift
// GroveTests
//
// GitHub (REST + GraphQL) and GitLab (REST) against a fake HTTP client: what's read, and every write request sent.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct HostingAPITests {

    private func body(_ request: URLRequest?) -> [String: Any] {
        request?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    private func github(_ http: FakeHTTPClient, host: String = "github.com") -> GitHubPullRequestHost {
        let account = HostingAccount(kind: .github, host: host, username: "octo")
        return GitHubPullRequestHost(location: RemoteLocation(kind: .github, host: host, owner: "o", name: "r"),
                                     client: RESTClient(credentials: RESTCredentials(account: account, secret: "tok"), http: http))
    }

    // MARK: GitHub

    private let listResponse = """
    {"data":{"repository":{"pullRequests":{"nodes":[
      {"number":12,"title":"Add login","body":"","url":"https://github.com/o/r/pull/12","state":"OPEN","isDraft":true,
       "headRefName":"feature/login","baseRefName":"main","createdAt":"2026-09-01T10:00:00Z","updatedAt":"2026-09-02T10:00:00Z",
       "author":{"login":"jane","avatarUrl":"https://a/1"},"labels":{"nodes":[{"name":"ui","color":"ff0000"}]},
       "reviewRequests":{"nodes":[{"requestedReviewer":{"login":"bob"}},{"requestedReviewer":{"name":"core"}}]},
       "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}},
      {"number":9,"title":"Old","state":"MERGED","headRefName":"old","baseRefName":"main","createdAt":"2026-08-01T10:00:00Z",
       "author":null,"labels":{"nodes":[]},"reviewRequests":{"nodes":[]},"commits":{"nodes":[{"commit":{"statusCheckRollup":null}}]}}
    ]}}}}
    """

    @Test func githubListsPullRequestsThroughGraphQL() async throws {
        let http = FakeHTTPClient { [listResponse] _ in (200, listResponse) }
        let prs = try await github(http).pullRequests()
        #expect(prs.map(\.id) == [12, 9])
        #expect(prs[0].isDraft && prs[0].body == nil && prs[0].checksStatus == .failing && prs[0].reviewers == ["bob", "core"])
        #expect(prs[0].labels.first?.color == "ff0000" && prs[1].state == .merged && prs[1].authorName == "ghost")
        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "POST" && request.url?.absoluteString == "https://api.github.com/graphql")
        let query = body(request)["query"] as? String ?? ""
        #expect(query.contains("$count: Int!") && !query.contains("$states"), "Only used variables are declared")
        #expect((body(request)["variables"] as? [String: Any])?["owner"] as? String == "o")
    }

    @Test func githubIndexesOpenAndMergedPullRequestsByBranch() async throws {
        let response = """
        {"data":{"repository":{
          "open":{"nodes":[{"number":14,"title":"Again","headRefName":"feature/login","headRefOid":"bbb","isDraft":false,"url":"u14"}]},
          "merged":{"nodes":[{"number":12,"title":"Login","headRefName":"feature/login","headRefOid":"aaa","isDraft":false,"url":"u12"},
                             {"number":9,"title":"Old","headRefName":"old","headRefOid":"ccc","isDraft":false,"url":"u9"}]}}}}
        """
        let index = BranchPullRequest.index(try await github(FakeHTTPClient { _ in (200, response) }).branchPullRequests())
        #expect(index["feature/login"]?.number == 14 && index["feature/login"]?.isMerged == false, "Open wins over merged")
        #expect(index["old"]?.isMerged == true && index["old"]?.headSHA == "ccc")
    }

    @Test func githubGraphQLErrorsSurface() async {
        let host = github(FakeHTTPClient { _ in (200, #"{"errors":[{"message":"Could not resolve to a Repository"}]}"#) })
        await #expect(throws: HostingError.unsupported("Could not resolve to a Repository")) { _ = try await host.pullRequests() }
    }

    @Test func githubListsWithoutTeamNamesWhenTheTokenLacksReadOrg() async throws {
        let refusal = #"{"errors":[{"type":"INSUFFICIENT_SCOPES","message":"The 'name' field requires one of the following scopes: ['read:org']"}]}"#
        let http = FakeHTTPClient { [listResponse] request in
            let query = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            return (200, query.contains("on Team") ? refusal : listResponse)
        }
        let prs = try await github(http).pullRequests()
        #expect(prs.map(\.id) == [12, 9] && http.requests.count == 2)
        #expect(prs[0].reviewers == ["bob", "core"], "Reviewers the token may see are still listed")

        // A token refused for everything still fails, as a permission problem.
        let refused = github(FakeHTTPClient { _ in (200, refusal) })
        await #expect(throws: HostingError.http(status: 403, message: "The 'name' field requires one of the following scopes: ['read:org']")) {
            _ = try await refused.pullRequests()
        }
    }

    @Test func githubWritesHitTheRESTEndpoints() async throws {
        let http = FakeHTTPClient { request in
            request.url?.path.hasSuffix("/pulls") == true
                ? (201, #"{"number":13,"html_url":"https://github.com/o/r/pull/13"}"#) : (200, "{}")
        }
        let host = github(http)
        let url = try await host.create(PullRequestDraft(base: "main", head: "feat", title: "T", body: "B", reviewers: ["bob"]))
        try await host.comment(number: 13, body: "Nice")
        try await host.merge(number: 13)
        try await host.close(number: 13)
        #expect(url == "https://github.com/o/r/pull/13")
        let sent = http.requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" }
        #expect(sent == ["POST /repos/o/r/pulls", "POST /repos/o/r/pulls/13/requested_reviewers", "POST /repos/o/r/issues/13/comments",
                         "PUT /repos/o/r/pulls/13/merge", "PATCH /repos/o/r/pulls/13"])
        #expect(body(http.requests[1])["reviewers"] as? [String] == ["bob"])
        #expect(body(http.requests[3])["merge_method"] as? String == "merge")
        #expect(body(http.requests[4])["state"] as? String == "closed")
        #expect(http.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer tok" })
    }

    @Test func githubEnterpriseUsesItsOwnAPI() async throws {
        let http = FakeHTTPClient { _ in (200, "diff --git a/x b/x\n") }
        let host = github(http, host: "ghe.example.com")
        _ = try await host.diff(number: 3)
        #expect(http.requests.first?.url?.absoluteString == "https://ghe.example.com/api/v3/repos/o/r/pulls/3")
        #expect(http.requests.first?.value(forHTTPHeaderField: "Accept") == "application/vnd.github.diff")
        #expect(host.headRef(number: 3) == "refs/pull/3/head")
    }

    @Test func githubConversationJoinsCommentsAndReviews() async throws {
        let http = FakeHTTPClient { request in
            request.url?.path.contains("/reviews") == true
                ? (200, #"[{"id":2,"user":{"login":"bob"},"body":"LGTM","submitted_at":"2026-09-01T12:00:00Z"},{"id":3,"body":""}]"#)
                : (200, #"[{"id":1,"user":{"login":"jane"},"body":"First","created_at":"2026-09-01T11:00:00Z"}]"#)
        }
        let comments = try await github(http).comments(number: 1)
        #expect(comments.map(\.body) == ["First", "LGTM"] && comments[1].isReview)
    }

    @Test func pagesFollowTheLinkHeader() {
        let link = #"<https://api.github.com/user/repos?page=2>; rel="next", <https://api.github.com/user/repos?page=5>; rel="last""#
        #expect(RESTClient.nextPage(link)?.absoluteString == "https://api.github.com/user/repos?page=2")
        #expect(RESTClient.nextPage(#"<https://x/?page=1>; rel="prev""#) == nil)
        #expect(RESTClient.nextPage(nil) == nil)
    }

    // MARK: GitLab

    private func gitlab(_ http: FakeHTTPClient) -> GitLabPullRequestHost {
        let account = HostingAccount(kind: .gitlab, host: "gitlab.example.com", username: "tanuki")
        return GitLabPullRequestHost(location: RemoteLocation(kind: .gitlab, host: "gitlab.example.com", owner: "group/sub", name: "app"),
                                     client: RESTClient(credentials: RESTCredentials(account: account, secret: "glpat"), http: http))
    }

    @Test func gitlabWritesHitTheRESTEndpoints() async throws {
        let http = FakeHTTPClient { request in
            if request.url?.path == "/api/v4/users" { return (200, #"[{"id":42,"username":"bob"}]"#) }
            return (201, #"{"iid":5,"web_url":"https://gitlab.example.com/group/sub/app/-/merge_requests/5"}"#)
        }
        let host = gitlab(http)
        let url = try await host.create(PullRequestDraft(base: "main", head: "feat", title: "T", body: "B", isDraft: true, reviewers: ["bob"]))
        try await host.comment(number: 5, body: "Hi")
        try await host.merge(number: 5)
        try await host.close(number: 5)
        #expect(url.hasSuffix("/merge_requests/5"))
        let project = "/api/v4/projects/group%2Fsub%2Fapp"
        let sent = http.requests.map { request in
            "\(request.httpMethod ?? "") \(request.url?.absoluteString.components(separatedBy: "example.com").last ?? "")"
        }
        #expect(sent == ["GET /api/v4/users?username=bob", "POST \(project)/merge_requests", "POST \(project)/merge_requests/5/notes",
                         "PUT \(project)/merge_requests/5/merge", "PUT \(project)/merge_requests/5"])
        #expect(body(http.requests[1])["reviewer_ids"] as? [Int] == [42] && body(http.requests[1])["title"] as? String == "Draft: T")
        #expect(body(http.requests[4])["state_event"] as? String == "close")
        #expect(host.headRef(number: 5) == "refs/merge-requests/5/head")
    }

    // MARK: Checkout

    @Test func checkoutFetchesTheHeadWithGit() {
        #expect(GitRepository.checkoutSteps(branch: "feat", remote: "origin", headRef: "refs/pull/7/head", hasLocalBranch: false,
                                            branchOnRemote: true)
                == [["fetch", "origin", "feat"], ["checkout", "-b", "feat", "--track", "origin/feat"]])
        #expect(GitRepository.checkoutSteps(branch: "feat", remote: "origin", headRef: "refs/pull/7/head", hasLocalBranch: true,
                                            branchOnRemote: true)
                == [["fetch", "origin", "feat"], ["checkout", "feat"], ["merge", "--ff-only", "origin/feat"]])
        // A fork's branch isn't on origin, so the pull request's head ref is fetched into the branch.
        #expect(GitRepository.checkoutSteps(branch: "fix", remote: "origin", headRef: "refs/pull/7/head", hasLocalBranch: false,
                                            branchOnRemote: false)
                == [["fetch", "origin", "refs/pull/7/head:refs/heads/fix"], ["checkout", "fix"]])
        #expect(GitRepository.checkoutSteps(branch: "fix", remote: "origin", headRef: "refs/pull/7/head", hasLocalBranch: true,
                                            branchOnRemote: false)
                == [["checkout", "fix"], ["fetch", "origin", "refs/pull/7/head"], ["merge", "--ff-only", "FETCH_HEAD"]])
    }
}
