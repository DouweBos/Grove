// CIRunDetailTests.swift
// GroveTests
//
// A run's jobs: read on selection, cached once the run is finished, re-read while it's still going.

import Foundation
import Testing
@testable import Grove

@MainActor
struct CIRunDetailTests {

    private let finished = MockData.ciRuns[2]
    private let failed = MockData.ciRuns[3]
    private let active = MockData.ciRuns[0]

    @Test func selectingARunLoadsItsJobs() async {
        let repo = MockGitRepository()
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        #expect(vm.detail.run?.id == active.id && !vm.detail.jobs.isEmpty, "The first run's jobs load with the list")

        await vm.select(failed)

        #expect(vm.detail.run?.id == failed.id && vm.detail.jobs.map(\.runID) == [failed.id, failed.id])
        #expect(vm.detail.jobs.flatMap(\.steps).contains { $0.status == .failure })
        #expect(!vm.detail.isLoadingJobs && vm.detail.jobsError == nil)
    }

    @Test func theFirstFailedJobIsSelected() async {
        let repo = MockGitRepository()
        let detail = CIRunDetailViewModel(repository: repo)

        await detail.show(failed)
        #expect(detail.selectedJob?.status == .failure && detail.selectedJob?.id != detail.jobs.first?.id)

        await detail.show(finished)
        #expect(detail.selectedJob?.id == detail.jobs.first?.id)
    }

    @Test func finishedRunsComeFromTheCache() async {
        let repo = MockGitRepository()
        let detail = CIRunDetailViewModel(repository: repo)
        await detail.show(finished)
        await detail.show(failed)

        await detail.show(finished)
        await detail.show(finished)

        #expect(repo.ci.jobRequests == [finished.id, failed.id])
        #expect(detail.jobs.allSatisfy { $0.runID == finished.id })
    }

    @Test func activeRunsAreReadAgainAndKeepTheSelectedJob() async {
        let repo = MockGitRepository()
        let detail = CIRunDetailViewModel(repository: repo)
        await detail.show(active)
        let second = detail.jobs[1]
        await detail.selectJob(second)

        await detail.show(active)

        #expect(repo.ci.jobRequests == [active.id, active.id])
        #expect(detail.selectedJob?.id == second.id)
    }

    @Test func aReRunMissesTheCache() async {
        let repo = MockGitRepository()
        let detail = CIRunDetailViewModel(repository: repo)
        await detail.show(finished)
        let rerun = CIRun(id: finished.id, number: finished.number, attempt: finished.attempt + 1, title: finished.title,
                          workflowID: finished.workflowID, workflowName: finished.workflowName, event: finished.event,
                          branch: finished.branch, headSHA: finished.headSHA, status: .success, actor: finished.actor,
                          createdDate: finished.createdDate, updatedDate: finished.updatedDate, startedDate: finished.startedDate,
                          webURL: finished.webURL)

        await detail.show(rerun)

        #expect(repo.ci.jobRequests == [finished.id, finished.id])
    }

    @Test func aFailedReadSaysSoAndCanBeRetried() async {
        let repo = MockGitRepository()
        repo.ci.error = .http(status: 500, message: "Boom")
        let detail = CIRunDetailViewModel(repository: repo)

        await detail.show(finished)
        #expect(detail.jobsError == "Boom" && detail.jobs.isEmpty && !detail.isLoadingJobs)

        repo.ci.error = nil
        await detail.reload()
        #expect(detail.jobsError == nil && !detail.jobs.isEmpty)
    }

    @Test func noSelectionClearsTheDetail() async {
        let detail = CIRunDetailViewModel(repository: MockGitRepository())
        await detail.show(finished)
        await detail.show(nil)
        #expect(detail.run == nil && detail.jobs.isEmpty && detail.selectedJob == nil)
    }
}

// MARK: - Artifacts

@MainActor
struct CIArtifactTests {

    private let finished = MockData.ciRuns[2]
    private let active = MockData.ciRuns[0]

    @Test func theZipIsDownloadedFromTheRedirectWithoutTheToken() async throws {
        let http = FakeHTTPClient(responses: { request in
            request.url?.host == "api.github.com"
                ? .init(status: 302, headers: ["Location": "https://blob.example.net/artifact.zip?sig=abc"])
                : .init(body: Data([0x50, 0x4B, 0x03, 0x04]))
        })
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("grove-artifact-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: destination) }

        try await CIHostTests.github(http).downloadArtifact(id: 9, to: destination)

        #expect(try Data(contentsOf: destination) == Data([0x50, 0x4B, 0x03, 0x04]))
        #expect(http.requests.map { $0.url?.absoluteString ?? "" } == [
            "https://api.github.com/repos/o/r/actions/artifacts/9/zip", "https://blob.example.net/artifact.zip?sig=abc"
        ])
        #expect(http.requests[1].value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func anExpiredArtifactFailsWithoutWritingAFile() async {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("grove-artifact-\(UUID().uuidString).zip")
        let host = CIHostTests.github(FakeHTTPClient { _ in (410, #"{"message":"Artifact has expired"}"#) })
        await #expect(throws: HostingError.http(status: 410, message: "Artifact has expired")) {
            try await host.downloadArtifact(id: 9, to: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func aFinishedRunsArtifactsLoadOnceWithItsJobs() async {
        let repo = MockGitRepository()
        let detail = CIRunDetailViewModel(repository: repo)

        await detail.show(finished)
        await detail.show(MockData.ciRuns[3])
        await detail.show(finished)

        #expect(detail.artifacts.map(\.name) == ["Grove-\(finished.shortSHA).app", "test-results"])
        #expect(repo.ci.artifactRequests == [finished.id, MockData.ciRuns[3].id])
    }

    @Test func aRunningRunsArtifactsAreOnlyReadWhileTheirTabIsOpen() async {
        let repo = MockGitRepository()
        let detail = CIRunDetailViewModel(repository: repo)
        await detail.show(active)
        await detail.show(active)
        #expect(repo.ci.artifactRequests.isEmpty)

        await detail.selectTab(.artifacts)
        await detail.show(active)
        #expect(repo.ci.artifactRequests == [active.id, active.id] && detail.activeTab == .artifacts)
    }

    @Test func downloadingSavesWhereTheUserChose() async throws {
        let repo = MockGitRepository()
        let detail = CIRunDetailViewModel(repository: repo)
        await detail.show(finished)
        let artifact = try #require(detail.artifacts.first)
        let destination = URL(fileURLWithPath: "/tmp/grove-tests/artifact.zip")

        detail.chooseDestination = { _ in nil }
        await detail.downloadArtifact(artifact)
        #expect(repo.ci.downloads.isEmpty && detail.downloads[artifact.id] == nil, "Cancelling the save panel downloads nothing")

        detail.chooseDestination = { _ in destination }
        await detail.downloadArtifact(artifact)
        #expect(repo.ci.downloads.map(\.id) == [artifact.id] && repo.ci.downloads.first?.destination == destination)
        #expect(detail.downloads[artifact.id] == .saved(destination))
    }

    @Test func aFailedDownloadSaysWhyAndExpiredOnesAreNotTried() async throws {
        let repo = MockGitRepository()
        let detail = CIRunDetailViewModel(repository: repo)
        detail.chooseDestination = { _ in URL(fileURLWithPath: "/tmp/grove-tests/artifact.zip") }
        await detail.show(finished)
        let artifact = try #require(detail.artifacts.first)

        repo.ci.error = .http(status: 403, message: "Forbidden")
        await detail.downloadArtifact(artifact)
        #expect(detail.downloads[artifact.id] == .failed("Forbidden"))

        repo.ci.error = nil
        let expired = CIArtifact(id: 1, name: "old", sizeInBytes: 1, isExpired: true, createdDate: .distantPast, expiresDate: nil)
        await detail.downloadArtifact(expired)
        #expect(repo.ci.downloads.isEmpty && detail.downloads[expired.id] == nil)
    }
}
