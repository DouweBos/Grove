// CIPollingTests.swift
// GroveTests
//
// Live updates: how often the Actions tab polls, and what one poll reads.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct CIPollingTests {

    // MARK: Schedule

    @Test func activeRunsPollFastThenEaseOff() {
        #expect(CIPollSchedule.interval(activeFor: 0) == 5)
        #expect(CIPollSchedule.interval(activeFor: 29) == 5)
        #expect(CIPollSchedule.interval(activeFor: 30) == 10)
        #expect(CIPollSchedule.interval(activeFor: 119) == 10)
        #expect(CIPollSchedule.interval(activeFor: 120) == 30)
        #expect(CIPollSchedule.interval(activeFor: 3600) == 30)
        #expect(CIPollSchedule.interval(activeFor: nil) == 60)
    }

    @Test func failuresBackOffToFiveMinutes() {
        #expect(CIPollSchedule.interval(activeFor: 0, consecutiveFailures: 1) == 60)
        #expect(CIPollSchedule.interval(activeFor: 0, consecutiveFailures: 2) == 120)
        #expect(CIPollSchedule.interval(activeFor: nil, consecutiveFailures: 3) == 240)
        #expect(CIPollSchedule.interval(activeFor: nil, consecutiveFailures: 4) == 300)
        #expect(CIPollSchedule.interval(activeFor: nil, consecutiveFailures: 500) == 300)
    }

    // MARK: One poll

    @Test func aPollWithActiveRunsReadsOnlyWhatCanChange() async {
        let repo = MockGitRepository()
        // The running run is older than the newest page a poll reads.
        repo.ci.runs = (0..<12).map { run(200 - $0, .success, minutesAgo: Double($0)) } + [run(100, .inProgress, minutesAgo: 60)]
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        repo.ci.runs[12] = run(100, .success, minutesAgo: 60)
        repo.ci.runs.insert(run(201, .queued, minutesAgo: 0), at: 0)

        await vm.poll()

        #expect(repo.ci.queries.last?.limit == CIViewModel.pollPageSize && repo.ci.runRequests == [100])
        #expect(vm.runs.first?.id == 201 && vm.runs.count == 14, "New runs are added on top")
        #expect(vm.runs.last?.status == .success, "The run that was going is read by id")
        #expect(!vm.isLoading)
    }

    @Test func anIdlePollReadsTheWholeListQuietly() async {
        let repo = MockGitRepository()
        repo.ci.runs = [run(1, .success, minutesAgo: 5)]
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        repo.ci.runs = []

        await vm.poll()

        #expect(repo.ci.queries.last?.limit == CIRunQuery.pageSize && vm.runs.isEmpty && repo.ci.runRequests.isEmpty)
    }

    @Test func aRunThatLeavesTheStatusFilterIsDropped() {
        let going = run(1, .inProgress, minutesAgo: 1)
        let merged = CIViewModel.merge([run(1, .success, minutesAgo: 1), run(2, .inProgress, minutesAgo: 0)], into: [going],
                                       query: CIRunQuery(status: .inProgress))
        #expect(merged.map(\.id) == [2])
    }

    @Test func aPollRefreshesTheSelectedRunsJobs() async {
        let repo = MockGitRepository()
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        let before = repo.ci.jobRequests.count

        await vm.poll()

        #expect(repo.ci.jobRequests.count == before + 1 && repo.ci.jobRequests.last == vm.selectedRunID)
    }

    // MARK: Loop

    @Test func theLoopFollowsTheScheduleUntilItsTaskEnds() async {
        let repo = MockGitRepository()
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        let waits = Waits(limit: 4)

        await vm.pollWhileVisible { interval in
            try await waits.record(interval) { step in
                // Everything finishes after the first poll, then the host starts failing.
                if step == 1 { repo.ci.runs = [self.run(1, .success, minutesAgo: 1)] }
                if step == 2 { repo.ci.error = .http(status: 429, message: "Slow down") }
            }
        }

        #expect(await waits.intervals == [5, 60, 60, 120])
        #expect(vm.consecutiveFailures == 2 && vm.pollInterval == 120)
        #expect(vm.runs.map(\.id) == [146, 145, 144, 143, 1], "Active runs deleted on the host are dropped; a failed poll keeps the list")
    }

    @Test func pollNowCutsTheWaitShort() async {
        let repo = MockGitRepository()
        repo.ci.runs = [run(1, .success, minutesAgo: 1)]
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        let loop = Task { await vm.pollWhileVisible() }
        await waitUntil { vm.pollWait != nil }
        let before = repo.ci.queries.count

        vm.pollNow()
        await waitUntil { repo.ci.queries.count > before }

        #expect(repo.ci.queries.count == before + 1, "Polled at once instead of after the idle minute")
        loop.cancel()
        await loop.value
    }

    // MARK: Helpers

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<400 where !condition() { try? await Task.sleep(for: .milliseconds(25)) }
    }

    private nonisolated func run(_ id: Int, _ status: CIRunStatus, minutesAgo: Double) -> CIRun {
        let date = Date(timeIntervalSince1970: 1_790_000_000 - minutesAgo * 60)
        return CIRun(id: id, number: id, attempt: 1, title: "Run \(id)", workflowID: 1, workflowName: "CI", event: "push", branch: "main",
                     headSHA: "abc", status: status, actor: "jane", createdDate: date, updatedDate: date, startedDate: date, webURL: "")
    }
}

/// Records the waits the poll loop asks for and ends the loop after `limit` of them.
private actor Waits {
    private(set) var intervals: [TimeInterval] = []
    private let limit: Int

    init(limit: Int) { self.limit = limit }

    func record(_ interval: TimeInterval, then change: @MainActor @Sendable (Int) -> Void) async throws {
        intervals.append(interval)
        if intervals.count >= limit { throw CancellationError() }
        await change(intervals.count)
    }
}

// MARK: - Paging

@MainActor
struct CIPagingTests {

    private nonisolated func runs(_ count: Int, from newest: Int = 1000, status: CIRunStatus = .success) -> [CIRun] {
        (0..<count).map { offset in
            let id = newest - offset
            let date = Date(timeIntervalSince1970: 1_790_000_000 + Double(id))
            return CIRun(id: id, number: id, attempt: 1, title: "Run \(id)", workflowID: 1, workflowName: "CI", event: "push",
                         branch: "main", headSHA: "abc", status: status, actor: "jane", createdDate: date, updatedDate: date,
                         startedDate: date, webURL: "")
        }
    }

    @Test func theHostIsAskedForTheNextPage() async throws {
        let http = FakeHTTPClient { _ in (200, #"{"workflow_runs":[]}"#) }
        _ = try await CIHostTests.github(http).runs(CIRunQuery(branch: "main").page(3))
        #expect(http.requests[0].url?.query == "per_page=50&branch=main&page=3")
    }

    @Test func scrollingToTheEndAddsTheNextPage() async {
        let repo = MockGitRepository()
        repo.ci.runs = runs(120)
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        #expect(vm.runs.count == 50 && vm.hasMoreRuns)

        await vm.loadMore()
        #expect(vm.runs.count == 100 && vm.hasMoreRuns && repo.ci.queries.last?.page == 2)
        await vm.loadMore()
        #expect(vm.runs.count == 120 && !vm.hasMoreRuns)
        #expect(vm.runs.map(\.id) == repo.ci.runs.map(\.id), "Pages line up without gaps or repeats")

        await vm.loadMore()
        #expect(repo.ci.queries.count == 3, "Nothing is read past the last page")
    }

    @Test func aShortFirstPageHasNoMore() async {
        let repo = MockGitRepository()
        repo.ci.runs = runs(12)
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        #expect(!vm.hasMoreRuns)
        await vm.loadMore()
        #expect(repo.ci.queries.count == 1)
    }

    @Test func changingAFilterStartsAtTheFirstPageAgain() async {
        let repo = MockGitRepository()
        repo.ci.runs = runs(120)
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        await vm.loadMore()

        await vm.setStatusFilter(.success)

        #expect(vm.runs.count == 50 && repo.ci.queries.last == CIRunQuery(status: .success))
    }

    @Test func pollsKeepTheLoadedPages() async {
        let repo = MockGitRepository()
        repo.ci.runs = runs(120)
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        await vm.loadMore()

        // Idle: the first page is read again and merged, not swapped in.
        repo.ci.runs.insert(contentsOf: runs(1, from: 1001), at: 0)
        await vm.poll()
        #expect(vm.runs.count == 100 && vm.runs.first?.id == 1001 && repo.ci.queries.last?.page == 1)

        // Active: the newest few and the running ones, still keeping the rest.
        repo.ci.runs.insert(contentsOf: runs(1, from: 1002, status: .inProgress), at: 0)
        await vm.poll()
        await vm.poll()
        #expect(vm.runs.count == 100 && vm.runs.first?.status == .inProgress)
        #expect(repo.ci.queries.last?.limit == CIViewModel.pollPageSize)
    }

    @Test func aPageForAnOutdatedFilterIsDropped() async {
        let repo = MockGitRepository()
        repo.ci.runs = runs(120)
        let vm = CIViewModel(repository: repo)
        await vm.refresh()

        async let more: Void = vm.loadMore()
        async let filter: Void = vm.setStatusFilter(.success)
        _ = await (more, filter)

        #expect(vm.runs.count == 50 && vm.runs.map(\.id) == Array(repo.ci.runs.prefix(50)).map(\.id))
    }

    @Test func aFailedPageSaysSoAndKeepsTheList() async {
        let repo = MockGitRepository()
        repo.ci.runs = runs(120)
        let vm = CIViewModel(repository: repo)
        await vm.refresh()
        repo.ci.error = .http(status: 502, message: "Bad Gateway")

        await vm.loadMore()

        #expect(vm.actionError == "Couldn\u{2019}t load more runs: Bad Gateway" && vm.runs.count == 50 && vm.hasMoreRuns)
        #expect(!vm.isLoadingMore)
    }
}
