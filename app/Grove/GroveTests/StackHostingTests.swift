// StackHostingTests.swift
// GroveTests
//
// What stacks need from each host: open plus recently merged pull requests with base and head, and retargeting a base.

import Foundation
import Testing
@testable import Grove

@MainActor
struct StackHostingTests {

    private func body(_ request: URLRequest?) -> [String: Any] {
        request?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
    }

    private func credentials(_ kind: HostingServiceKind, host: String) -> RESTCredentials {
        let account = kind == .azureDevOps ? HostingAccount(kind: kind, username: "me", organization: "org")
            : HostingAccount(kind: kind, host: host, username: "me")
        return RESTCredentials(account: account, secret: "token")
    }

    private func github(_ http: FakeHTTPClient) -> GitHubPullRequestHost {
        GitHubPullRequestHost(location: RemoteLocation(kind: .github, host: "github.com", owner: "o", name: "r"),
                              client: RESTClient(credentials: credentials(.github, host: "github.com"), http: http))
    }

    @Test func githubReadsOpenAndMergedRowsInOneQuery() async throws {
        let response = """
        {"data":{"repository":{
          "open":{"nodes":[{"number":6330,"title":"Cast connect","headRefName":"19-cast","baseRefName":"18-chromecast",
            "headRefOid":"bbb","state":"OPEN","isDraft":true,"url":"u1",
            "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}}]},
          "merged":{"nodes":[{"number":6329,"title":"Chromecast","headRefName":"18-chromecast","baseRefName":"main",
            "headRefOid":"aaa","state":"MERGED","isDraft":false,"url":"u0","commits":{"nodes":[]}}]}}}}
        """
        let http = FakeHTTPClient { [response] _ in (200, response) }
        let rows = try await github(http).branchPullRequests()
        #expect(rows.map(\.number) == [6330, 6329])
        #expect(rows[0].baseBranch == "18-chromecast" && rows[0].headSHA == "bbb" && rows[0].checks == .passing)
        #expect(rows[1].isMerged && rows[1].headSHA == "aaa")
        let query = body(http.requests.first)["query"] as? String ?? ""
        #expect(query.contains("states: [MERGED]") && query.contains("headRefOid"))
        let index = BranchPullRequest.index(rows)
        #expect(index["19-cast"]?.isMerged == false && index["18-chromecast"]?.isMerged == true)
    }

    @Test func everyHostRetargetsABase() async throws {
        let http = FakeHTTPClient { _ in (200, "{}") }
        try await github(http).updateBase(number: 12, base: "main")
        let gitlab = GitLabPullRequestHost(location: RemoteLocation(kind: .gitlab, host: "gitlab.com", owner: "g", name: "app"),
                                           client: RESTClient(credentials: credentials(.gitlab, host: "gitlab.com"), http: http))
        try await gitlab.updateBase(number: 5, base: "main")
        let bitbucket = BitbucketPullRequestHost(location: RemoteLocation(kind: .bitbucket, host: "bitbucket.org", owner: "ws", name: "repo"),
                                                 client: RESTClient(credentials: credentials(.bitbucket, host: "bitbucket.org"), http: http))
        try await bitbucket.updateBase(number: 7, base: "main")
        let azure = AzureDevOpsPullRequestHost(
            location: RemoteLocation(kind: .azureDevOps, host: "dev.azure.com", owner: "org", name: "repo", project: "proj"),
            client: RESTClient(credentials: credentials(.azureDevOps, host: "dev.azure.com"), http: http))
        try await azure.updateBase(number: 9, base: "main")

        let sent = http.requests
        #expect(sent.map(\.httpMethod) == ["PATCH", "PUT", "PUT", "PATCH"])
        #expect(sent[0].url?.path == "/repos/o/r/pulls/12" && body(sent[0])["base"] as? String == "main")
        #expect(sent[1].url?.path.hasSuffix("/merge_requests/5") == true && body(sent[1])["target_branch"] as? String == "main")
        #expect(((body(sent[2])["destination"] as? [String: Any])?["branch"] as? [String: Any])?["name"] as? String == "main")
        #expect(sent[3].url?.path.hasSuffix("/pullrequests/9") == true && body(sent[3])["targetRefName"] as? String == "refs/heads/main")
    }

    @Test func mergedParentsGroupTheirChildren() {
        let vm = StackViewModel(repository: MockGitRepository(), refs: RepositoryRefs(repository: MockGitRepository()))
        let merged = BranchPullRequest(number: 1, title: "a", headBranch: "a", isDraft: false, url: "", isMerged: true)
        let layers = ["b", "c"].enumerated().map { index, name in
            StackLayer(branch: name, tipSHA: name, parent: "a", base: "a", commits: [name], health: [.parentMerged],
                       pullRequest: nil, mergedParent: merged, ahead: 0, behind: 0, hasUpstream: true, isHEAD: false,
                       worktreePath: nil, depth: index)
        }
        let groups = vm.mergedParents(BranchStack(name: "s", trunk: "main", layers: layers))
        #expect(groups.map(\.branch) == ["a"])
        #expect(groups.first?.children.map(\.branch) == ["b", "c"])
        #expect(groups.first?.pullRequest?.number == 1)
    }
}
