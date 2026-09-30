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
        detail.selectJob(second)

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
