// CIHostTests.swift
// GroveTests
//
// GitHub Actions against a fake HTTP client: which endpoints are read and how their JSON maps to runs, jobs and artifacts.

import Foundation
import Testing
@testable import Grove

@MainActor
struct CIHostTests {

    static func github(_ http: FakeHTTPClient, host: String = "github.com") -> GitHubCIHost {
        let account = HostingAccount(kind: .github, host: host, username: "octo")
        return GitHubCIHost(location: RemoteLocation(kind: .github, host: host, owner: "o", name: "r"),
                            client: RESTClient(credentials: RESTCredentials(account: account, secret: "tok"), http: http))
    }

    private func paths(_ http: FakeHTTPClient) -> [String] {
        http.requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")\($0.url?.query.map { "?" + $0 } ?? "")" }
    }

    nonisolated static let runsResponse = """
    {"total_count":2,"workflow_runs":[
      {"id":30,"name":"CI","display_title":"Fix login","run_number":12,"run_attempt":2,"event":"push","status":"in_progress",
       "conclusion":null,"workflow_id":7,"head_branch":"feature/login","head_sha":"abcdef1234567890","html_url":"https://github.com/o/r/actions/runs/30",
       "created_at":"2026-09-01T10:00:00Z","updated_at":"2026-09-01T10:05:00Z","run_started_at":"2026-09-01T10:04:00Z",
       "actor":{"login":"jane"},"triggering_actor":{"login":"bob"}},
      {"id":29,"name":"Release","display_title":"","run_number":3,"event":"workflow_dispatch","status":"completed",
       "conclusion":"timed_out","workflow_id":8,"head_branch":null,"head_sha":"1111111","created_at":"2026-08-31T10:00:00Z",
       "actor":{"login":"jane"}}
    ]}
    """

    // MARK: Runs

    @Test func runsMapStatusAttemptAndActor() async throws {
        let http = FakeHTTPClient { _ in (200, Self.runsResponse) }
        let runs = try await Self.github(http).runs(CIRunQuery())
        #expect(runs.map(\.id) == [30, 29])
        #expect(runs[0].status == .inProgress && runs[0].attempt == 2 && runs[0].number == 12 && runs[0].actor == "bob")
        #expect(runs[0].title == "Fix login" && runs[0].workflowName == "CI" && runs[0].shortSHA == "abcdef1")
        #expect(runs[0].startedDate == GitDate.parse("2026-09-01T10:04:00Z"))
        #expect(runs[1].status == .failure && runs[1].title == "Release" && runs[1].branch == nil && runs[1].attempt == 1)
        #expect(runs[1].updatedDate == runs[1].createdDate && runs[1].startedDate == nil)
        #expect(paths(http) == ["GET /repos/o/r/actions/runs?per_page=50"])
        #expect(http.requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(http.requests[0].cachePolicy == .reloadIgnoringLocalCacheData, "A poll must not be answered from URLCache")
    }

    @Test func filtersBecomeThePathAndQuery() async throws {
        let http = FakeHTTPClient { _ in (200, #"{"workflow_runs":[]}"#) }
        let host = Self.github(http, host: "ghe.example.com")
        _ = try await host.runs(CIRunQuery(workflowID: 7, branch: "feature/a+b&c", status: .inProgress))
        _ = try await host.runs(CIRunQuery(status: .failure).limited(to: 10))
        #expect(http.requests.map { $0.url?.absoluteString ?? "" } == [
            "https://ghe.example.com/api/v3/repos/o/r/actions/workflows/7/runs?per_page=50&branch=feature/a%2Bb%26c&status=in_progress",
            "https://ghe.example.com/api/v3/repos/o/r/actions/runs?per_page=10&status=failure"
        ])
    }

    @Test func everyConclusionFoldsIntoAStatus() {
        let status = GitHubCIParser.status
        #expect(status("queued", nil) == .queued && status("waiting", nil) == .queued && status("requested", nil) == .queued)
        #expect(status("in_progress", nil) == .inProgress)
        #expect(status("completed", "success") == .success && status("completed", "failure") == .failure)
        #expect(status("completed", "startup_failure") == .failure && status("completed", "cancelled") == .cancelled)
        #expect(status("completed", "skipped") == .skipped && status("completed", "action_required") == .neutral)
        #expect(status("completed", nil) == .neutral)
        #expect(CIRunStatus.queued.isActive && CIRunStatus.inProgress.isActive && !CIRunStatus.failure.isActive)
    }

    @Test func aSingleRunIsReadByID() async throws {
        let http = FakeHTTPClient { _ in (200, #"{"id":30,"name":"CI","status":"completed","conclusion":"success","run_number":1}"#) }
        let run = try await Self.github(http).run(id: 30)
        #expect(run.status == .success && paths(http) == ["GET /repos/o/r/actions/runs/30"])
        let missing = Self.github(FakeHTTPClient { _ in (200, "{}") })
        await #expect(throws: HostingError.self) { _ = try await missing.run(id: 1) }
    }

    // MARK: Jobs, artifacts, workflows

    @Test func jobsCarryTheirStepsInOrder() async throws {
        let response = """
        {"total_count":1,"jobs":[{"id":5,"run_id":30,"name":"build","status":"completed","conclusion":"failure",
          "started_at":"2026-09-01T10:00:00Z","completed_at":"2026-09-01T10:02:30Z","html_url":"https://github.com/o/r/actions/runs/30/job/5",
          "steps":[{"name":"Test","status":"completed","conclusion":"failure","number":2,
                    "started_at":"2026-09-01T10:00:10Z","completed_at":"2026-09-01T10:02:30Z"},
                   {"name":"Set up job","status":"completed","conclusion":"success","number":1,
                    "started_at":"2026-09-01T10:00:00Z","completed_at":"2026-09-01T10:00:10Z"}]}]}
        """
        let http = FakeHTTPClient { _ in (200, response) }
        let jobs = try await Self.github(http).jobs(runID: 30)
        #expect(jobs.count == 1 && jobs[0].status == .failure && jobs[0].duration() == 150)
        #expect(jobs[0].steps.map(\.name) == ["Set up job", "Test"] && jobs[0].steps[1].status == .failure)
        #expect(jobs[0].steps[1].duration == 140)
        #expect(paths(http) == ["GET /repos/o/r/actions/runs/30/jobs?filter=latest&per_page=100"])
    }

    @Test func artifactsAndWorkflowsAreUnwrapped() async throws {
        let http = FakeHTTPClient { request in
            request.url?.path.hasSuffix("/artifacts") == true
                ? (200, #"{"artifacts":[{"id":9,"name":"app","size_in_bytes":2048,"expired":true,"created_at":"2026-09-01T10:00:00Z"}]}"#)
                : (200, #"{"workflows":[{"id":7,"name":"CI","path":".github/workflows/ci.yml","state":"active"},"#
                        + #"{"id":8,"name":"Old","path":".github/workflows/old.yml","state":"disabled_manually"}]}"#)
        }
        let host = Self.github(http)
        let artifacts = try await host.artifacts(runID: 30)
        let workflows = try await host.workflows()
        #expect(artifacts == [CIArtifact(id: 9, name: "app", sizeInBytes: 2048, isExpired: true,
                                         createdDate: GitDate.parse("2026-09-01T10:00:00Z")!, expiresDate: nil)])
        #expect(workflows.map(\.isEnabled) == [true, false] && workflows[0].path == ".github/workflows/ci.yml")
        #expect(paths(http) == ["GET /repos/o/r/actions/runs/30/artifacts?per_page=100", "GET /repos/o/r/actions/workflows?per_page=100"])
    }

    @Test func wrappedListsFollowTheLinkHeader() async throws {
        let http = FakeHTTPClient(responses: { request in
            request.url?.query?.contains("page=2") == true
                ? .init(body: Data(#"{"jobs":[{"id":2}]}"#.utf8))
                : .init(headers: ["Link": #"<https://api.github.com/repos/o/r/actions/runs/1/jobs?page=2>; rel="next""#],
                        body: Data(#"{"jobs":[{"id":1}]}"#.utf8))
        })
        let jobs = try await Self.github(http).jobs(runID: 1)
        #expect(jobs.map(\.id) == [1, 2] && http.requests.count == 2)
    }

    // MARK: Resolving

    @Test func otherServicesAreUnsupportedBeforeAnAccountIsAsked() {
        let store = makeAccountStore()
        let gitlab = [RemoteInfo(id: "origin", name: "origin", url: "https://gitlab.com/group/app.git", pushURL: nil)]
        #expect(throws: HostingError.ciUnsupported(.gitlab)) { _ = try CIHostResolver.resolve(remotes: gitlab, accounts: store) }
        #expect(HostLoadFailure(HostingError.ciUnsupported(.gitlab)) == .unsupportedHost(.gitlab))

        let github = [RemoteInfo(id: "upstream", name: "upstream", url: "git@bitbucket.org:ws/repo.git", pushURL: nil),
                      RemoteInfo(id: "origin", name: "origin", url: "git@github.com:o/r.git", pushURL: nil)]
        #expect(throws: HostingError.noAccount(.github, host: "github.com")) { _ = try CIHostResolver.resolve(remotes: github, accounts: store) }
        #expect(throws: HostingError.noHostedRemote) { _ = try CIHostResolver.resolve(remotes: [], accounts: store) }

        store.add(HostingAccount(kind: .github, username: "octo"), secret: "tok")
        #expect((try? CIHostResolver.resolve(remotes: github, accounts: store))?.kind == .github)
    }
}
