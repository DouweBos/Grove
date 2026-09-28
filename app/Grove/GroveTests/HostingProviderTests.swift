// HostingProviderTests.swift
// GroveTests
//
// Bitbucket and Azure DevOps against a fake HTTP client, and GitLab's parsers on API fixtures.

import Foundation
import Testing
@testable import Grove

@MainActor
struct HostingProviderTests {

    private func body(_ request: URLRequest) -> [String: Any] {
        request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    // MARK: Bitbucket

    private let bitbucketList = """
    {"values":[{"id":7,"title":"Add login","description":"Adds it","state":"OPEN","draft":true,
      "author":{"display_name":"Jane"},"source":{"branch":{"name":"feature/login"}},"destination":{"branch":{"name":"main"}},
      "created_on":"2026-09-01T10:00:00.000000+00:00","updated_on":"2026-09-02T10:00:00.000000+00:00",
      "reviewers":[{"display_name":"Bob"}]},
     {"id":6,"title":"Old","state":"DECLINED","source":{"branch":{"name":"old"}},"destination":{"branch":{"name":"main"}},
      "created_on":"2026-08-01T10:00:00+00:00"}]}
    """

    private func bitbucket(_ http: FakeHTTPClient) -> BitbucketPullRequestHost {
        let location = RemoteLocation(kind: .bitbucket, host: "bitbucket.org", owner: "ws", name: "repo")
        let credentials = RESTCredentials(account: HostingAccount(kind: .bitbucket, username: "me"), secret: "pw")
        return BitbucketPullRequestHost(location: location, client: RESTClient(credentials: credentials, http: http))
    }

    @Test func bitbucketListsAndIndexesPullRequests() async throws {
        let host = bitbucket(FakeHTTPClient { [bitbucketList] _ in (200, bitbucketList) })
        let prs = try await host.pullRequests()
        #expect(prs.map(\.id) == [7, 6])
        #expect(prs[0].isDraft && prs[0].sourceBranch == "feature/login" && prs[0].reviewers == ["Bob"])
        #expect(prs[1].state == .closed)
        let open = try await host.openPullRequests()
        #expect(open["feature/login"]?.url == "https://bitbucket.org/ws/repo/pull-requests/7")
        #expect(open["old"] == nil)
    }

    @Test func bitbucketWritesHitTheRightEndpoints() async throws {
        let http = FakeHTTPClient { _ in (201, #"{"id":8,"links":{"html":{"href":"https://bitbucket.org/ws/repo/pull-requests/8"}}}"#) }
        let host = bitbucket(http)
        let url = try await host.create(PullRequestDraft(base: "main", head: "feature/x", title: "T", body: "B", isDraft: true))
        try await host.comment(number: 8, body: "Nice")
        try await host.close(number: 8)
        try await host.merge(number: 8)
        #expect(url == "https://bitbucket.org/ws/repo/pull-requests/8")
        let requests = http.requests
        #expect(requests.map(\.httpMethod) == ["POST", "POST", "POST", "POST"])
        #expect(requests.map { $0.url?.path ?? "" } == [
            "/2.0/repositories/ws/repo/pullrequests", "/2.0/repositories/ws/repo/pullrequests/8/comments",
            "/2.0/repositories/ws/repo/pullrequests/8/decline", "/2.0/repositories/ws/repo/pullrequests/8/merge"
        ])
        let create = body(requests[0])
        #expect((create["source"] as? [String: Any]).flatMap { ($0["branch"] as? [String: Any])?["name"] as? String } == "feature/x")
        #expect(create["draft"] as? Bool == true)
        #expect((body(requests[1])["content"] as? [String: Any])?["raw"] as? String == "Nice")
        #expect(body(requests[3])["merge_strategy"] as? String == "merge_commit")
        #expect(requests[0].value(forHTTPHeaderField: "Authorization")?.hasPrefix("Basic ") == true)
    }

    @Test func bitbucketSplitsInlineComments() {
        let values: [[String: Any]] = [
            ["id": 1, "content": ["raw": "General"], "user": ["display_name": "A"], "created_on": "2026-09-01T10:00:00Z"],
            ["id": 2, "content": ["raw": "Line"], "user": ["display_name": "B"], "created_on": "2026-09-01T11:00:00Z",
             "inline": ["path": "a.swift", "to": 4]],
            ["id": 3, "content": ["raw": "Reply"], "user": ["display_name": "C"], "created_on": "2026-09-01T12:00:00Z",
             "inline": ["path": "a.swift", "to": 4], "parent": ["id": 2]],
            ["id": 4, "deleted": true, "content": ["raw": "Gone"], "created_on": "2026-09-01T12:00:00Z"]
        ]
        let parsed = BitbucketParser.comments(values)
        #expect(parsed.comments.map(\.body) == ["General"])
        #expect(PRReviewThread.threads(from: parsed.lineComments).first?.replies.map(\.body) == ["Reply"])
    }

    @Test func refusedTokenReadsAsSignedOut() async {
        let host = bitbucket(FakeHTTPClient { _ in (401, "") })
        await #expect(throws: HostingError.notSignedIn(.bitbucket)) { _ = try await host.pullRequests() }
    }

    // MARK: Azure DevOps

    private func azure(_ http: FakeHTTPClient) -> AzureDevOpsPullRequestHost {
        let location = RemoteLocation(kind: .azureDevOps, host: "dev.azure.com", owner: "org", name: "repo", project: "proj")
        let credentials = RESTCredentials(account: HostingAccount(kind: .azureDevOps, username: "me", organization: "org"), secret: "pat")
        return AzureDevOpsPullRequestHost(location: location, client: RESTClient(credentials: credentials, http: http))
    }

    @Test func azureParsesPullRequestsAndThreads() async throws {
        let list = """
        {"value":[{"pullRequestId":12,"title":"Fix","status":"active","isDraft":false,"createdBy":{"displayName":"Jane"},
          "sourceRefName":"refs/heads/fix/it","targetRefName":"refs/heads/main","creationDate":"2026-09-01T10:00:00Z",
          "labels":[{"name":"bug"}],"reviewers":[{"displayName":"Bob"}]}]}
        """
        let prs = try await azure(FakeHTTPClient { _ in (200, list) }).pullRequests()
        #expect(prs.first?.sourceBranch == "fix/it" && prs.first?.labels.map(\.name) == ["bug"])

        let threads: [[String: Any]] = [
            ["id": 1, "comments": [["id": 1, "content": "Looks good", "author": ["displayName": "A"], "commentType": "text",
                                    "publishedDate": "2026-09-01T10:00:00Z"]]],
            ["id": 2, "threadContext": ["filePath": "/src/a.swift", "rightFileStart": ["line": 9]],
             "comments": [["id": 1, "content": "Rename", "author": ["displayName": "B"], "publishedDate": "2026-09-01T11:00:00Z"],
                          ["id": 2, "parentCommentId": 1, "content": "Done", "author": ["displayName": "C"],
                           "publishedDate": "2026-09-01T12:00:00Z"]]],
            ["id": 3, "comments": [["id": 1, "content": "Voted", "commentType": "system"]]]
        ]
        let parsed = AzureDevOpsParser.threads(threads)
        #expect(parsed.comments.map(\.body) == ["Looks good"])
        let thread = PRReviewThread.threads(from: parsed.lineComments)
        #expect(thread.count == 1 && thread[0].root.path == "src/a.swift" && thread[0].root.line == 9)
        #expect(thread[0].replies.map(\.body) == ["Done"])
    }

    @Test func azureMergeCompletesOnTheSourceCommit() async throws {
        let http = FakeHTTPClient { request in
            request.httpMethod == "GET" ? (200, #"{"pullRequestId":12,"title":"Fix","lastMergeSourceCommit":{"commitId":"abc123"}}"#)
                : (200, "{}")
        }
        try await azure(http).merge(number: 12)
        let patch = http.requests.last
        #expect(patch?.httpMethod == "PATCH")
        #expect(patch?.url?.path == "/org/proj/_apis/git/repositories/repo/pullrequests/12")
        #expect(patch?.url?.query?.contains("api-version=7.1") == true)
        let sent = patch.map(body) ?? [:]
        #expect(sent["status"] as? String == "completed")
        #expect((sent["lastMergeSourceCommit"] as? [String: Any])?["commitId"] as? String == "abc123")
    }

    @Test func azureCreateAndCommentBodies() async throws {
        let http = FakeHTTPClient { _ in (201, #"{"pullRequestId":13}"#) }
        let host = azure(http)
        let url = try await host.create(PullRequestDraft(base: "main", head: "feat", title: "T", body: "B", isDraft: true))
        try await host.comment(number: 13, body: "Hi")
        try await host.close(number: 13)
        #expect(url == "https://dev.azure.com/org/proj/_git/repo/pullrequest/13")
        let requests = http.requests
        #expect(body(requests[0])["sourceRefName"] as? String == "refs/heads/feat")
        #expect(body(requests[0])["isDraft"] as? Bool == true)
        #expect(((body(requests[1])["comments"] as? [[String: Any]])?.first?["content"] as? String) == "Hi")
        #expect(requests[2].httpMethod == "PATCH" && body(requests[2])["status"] as? String == "abandoned")
    }

    @Test func azureSignInPageReadsAsSignedOut() async {
        let host = azure(FakeHTTPClient { _ in (203, "<html>Sign in</html>") })
        await #expect(throws: HostingError.notSignedIn(.azureDevOps)) { _ = try await host.pullRequests() }
    }

    // MARK: GitLab

    @Test func gitlabParsesMergeRequests() throws {
        let json = """
        [{"iid":5,"title":"Speed up CI","description":"","state":"merged","source_branch":"ci","target_branch":"main",
          "author":{"username":"jane","name":"Jane"},"created_at":"2026-09-01T10:00:00.000Z","updated_at":"2026-09-03T10:00:00.000Z",
          "draft":false,"labels":["ci"],"reviewers":[{"username":"bob"}],"head_pipeline":{"status":"failed"}},
         {"iid":6,"title":"WIP thing","state":"opened","source_branch":"wip","target_branch":"main","work_in_progress":true,
          "created_at":"2026-09-04T10:00:00Z"}]
        """
        let requests = HostingJSON.objects(json).compactMap(GitLabParser.mergeRequest)
        #expect(requests.map(\.id) == [5, 6])
        #expect(requests[0].state == .merged && requests[0].body == nil && requests[0].checksStatus == .failing)
        #expect(requests[0].reviewers == ["bob"] && requests[0].labels.map(\.name) == ["ci"])
        #expect(requests[1].isDraft && requests[1].state == .open)
    }

    @Test func gitlabDiscussionsSplitIntoConversationAndLines() {
        let discussions: [[String: Any]] = [
            ["notes": [["id": 1, "body": "General", "author": ["username": "a"], "created_at": "2026-09-01T10:00:00Z"]]],
            ["notes": [["id": 2, "body": "Line", "author": ["username": "b"], "created_at": "2026-09-01T11:00:00Z",
                        "position": ["new_path": "a.go", "new_line": 3]],
                       ["id": 3, "body": "Reply", "author": ["username": "c"], "created_at": "2026-09-01T12:00:00Z",
                        "position": ["new_path": "a.go", "new_line": 3]]]],
            ["notes": [["id": 4, "body": "added 1 commit", "system": true]]]
        ]
        let parsed = GitLabParser.discussions(discussions)
        #expect(parsed.comments.map(\.body) == ["General"])
        let threads = PRReviewThread.threads(from: parsed.lineComments)
        #expect(threads.count == 1 && threads[0].replies.map(\.body) == ["Reply"])
    }

    @Test func gitlabCreateArgumentsAndURL() {
        let draft = PullRequestDraft(base: "main", head: "feat", title: "T", body: "B", isDraft: true, reviewers: ["a"])
        let arguments = GitLabParser.createArguments(draft)
        #expect(arguments.starts(with: ["mr", "create", "--source-branch", "feat", "--target-branch", "main"]))
        #expect(arguments.contains("--draft") && arguments.contains("--yes") && arguments.suffix(2) == ["--reviewer", "a"])
        let output = "Creating merge request for feat into main in group/app\n\n!12 T (feat)\n https://gitlab.com/group/app/-/merge_requests/12\n"
        #expect(GitLabParser.mergeRequestURL(in: output) == "https://gitlab.com/group/app/-/merge_requests/12")
        #expect(GitLabCLI.parseAuthStatus("gitlab.com\n  ✓ Logged in to gitlab.com as jane (/Users/j/.config/glab-cli/config.yml)\n")
                    .first?.account == "jane")
        #expect(GitLabCLI.projectPath(RemoteLocation(kind: .gitlab, host: "gitlab.com", owner: "group/sub", name: "app"))
                == "projects/group%2Fsub%2Fapp")
    }
}
