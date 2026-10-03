// CIRunActionTests.swift
// GroveTests
//
// Re-running and cancelling runs: the requests sent, the confirmation in between, and the list catching up after.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct CIRunActionTests {

    @Test func rerunAndCancelPostToTheRunsEndpoints() async throws {
        let http = FakeHTTPClient { _ in (201, "{}") }
        let host = CIHostTests.github(http)

        try await host.rerun(runID: 30, failedOnly: false)
        try await host.rerun(runID: 30, failedOnly: true)
        try await host.cancel(runID: 30)

        #expect(http.requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } == [
            "POST /repos/o/r/actions/runs/30/rerun", "POST /repos/o/r/actions/runs/30/rerun-failed-jobs",
            "POST /repos/o/r/actions/runs/30/cancel"
        ])
        #expect(http.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer tok" && $0.httpBody == nil })
    }

    @Test func aRefusedWriteSurfacesTheHostsMessage() async {
        let host = CIHostTests.github(FakeHTTPClient { _ in (409, #"{"message":"Cannot cancel a workflow run that is completed."}"#) })
        await #expect(throws: HostingError.http(status: 409, message: "Cannot cancel a workflow run that is completed.")) {
            try await host.cancel(runID: 30)
        }
    }

    @Test func nothingIsSentUntilConfirmed() async {
        let repo = MockGitRepository()
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        let failed = MockData.ciRuns[3]

        vm.request(.rerunFailed, on: failed)
        #expect(vm.pendingOperation?.run.id == failed.id && repo.ci.operations.isEmpty)
        vm.cancelPendingOperation()
        #expect(vm.pendingOperation == nil && repo.ci.operations.isEmpty)
    }

    @Test func confirmingAReRunSendsItAndShowsTheNewAttempt() async throws {
        let repo = MockGitRepository()
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        let failed = MockData.ciRuns[3]
        await vm.select(failed)

        vm.request(.rerunFailed, on: failed)
        await vm.confirm(try #require(vm.pendingOperation))
        #expect(repo.ci.operations == ["rerun-failed \(failed.id)"] && vm.pendingOperation == nil && !vm.isPerforming)
        #expect(vm.selectedRun?.status == .queued && vm.selectedRun?.attempt == failed.attempt + 1)
        #expect(vm.detail.run?.attempt == failed.attempt + 1, "The detail follows the new attempt")
        #expect(vm.pollInterval == 5, "Polling is fast again after starting something")

        vm.request(.rerun, on: MockData.ciRuns[2])
        await vm.confirm(try #require(vm.pendingOperation))
        #expect(repo.ci.operations.last == "rerun \(MockData.ciRuns[2].id)")
    }

    @Test func confirmingACancelStopsTheRun() async throws {
        let repo = MockGitRepository()
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        let running = MockData.ciRuns[0]

        vm.request(.cancel, on: running)
        await vm.confirm(try #require(vm.pendingOperation))

        #expect(repo.ci.operations == ["cancel \(running.id)"])
        #expect(vm.runs.first { $0.id == running.id }?.status == .cancelled)
    }

    @Test func aFailedActionIsReportedAndChangesNothing() async throws {
        let repo = MockGitRepository()
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        let queriesBefore = repo.ci.queries.count
        repo.ci.error = .http(status: 403, message: "Resource not accessible by personal access token")

        vm.request(.rerun, on: MockData.ciRuns[2])
        await vm.confirm(try #require(vm.pendingOperation))

        #expect(vm.actionError == "Resource not accessible by personal access token" && !vm.isPerforming)
        #expect(repo.ci.queries.count == queriesBefore && vm.runs == MockData.ciRuns)
        vm.clearActionError()
        #expect(vm.actionError == nil)
    }

    @Test func onlyFailedOrCancelledRunsCanReRunTheirFailedJobs() {
        let vm = CIViewModel(repository: MockGitRepository())
        #expect(vm.canRerunFailed(MockData.ciRuns[3]) && vm.canRerunFailed(MockData.ciRuns[4]))
        #expect(!vm.canRerunFailed(MockData.ciRuns[2]) && !vm.canRerunFailed(MockData.ciRuns[0]))
    }
}
