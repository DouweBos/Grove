// CIRunWatcherTests.swift
// GroveTests
//
// Notifications for watched runs: when one is due, and how a dispatched run is found to watch.

import Foundation
import Testing
@testable import Grove

@MainActor
private final class RecordingNotifier: CIRunNotifying {
    var notified: [(run: CIRun, path: String)] = []
    func requestAuthorization() async {}
    func notify(_ run: CIRun, repositoryPath: String) { notified.append((run, repositoryPath)) }
}

@MainActor
struct CIRunWatcherTests {

    private let notifier = RecordingNotifier()
    // The loop never runs; tests poll by hand.
    private var watcher: CIRunWatcher { CIRunWatcher(notifier: notifier, sleep: { _ in throw CancellationError() }) }

    private func activeRun(in repo: MockGitRepository) -> CIRun {
        repo.ci.runs.first { $0.status.isActive }!
    }

    private func finish(_ id: Int, _ status: CIRunStatus, in repo: MockGitRepository) {
        let index = repo.ci.runs.firstIndex { $0.id == id }!
        repo.ci.runs[index] = repo.ci.runs[index].with(status: status, attempt: repo.ci.runs[index].attempt)
    }

    @Test func aWatchedRunIsAnnouncedOnceWhenItFinishes() async {
        let repo = MockGitRepository()
        let watcher = watcher
        let run = activeRun(in: repo)
        watcher.watch(run, in: "/repo", repository: repo)

        await watcher.poll()
        #expect(notifier.notified.isEmpty && watcher.isWatching(run.id, in: "/repo"))

        finish(run.id, .failure, in: repo)
        await watcher.poll()
        await watcher.poll()

        #expect(notifier.notified.map(\.run.id) == [run.id] && notifier.notified.first?.path == "/repo")
        #expect(notifier.notified.first?.run.status == .failure)
        #expect(!watcher.isWatching(run.id, in: "/repo"))
    }

    @Test func finishedRunsAreNotWatchedAndStoppingCancelsTheNotification() async {
        let repo = MockGitRepository()
        let watcher = watcher
        let finished = repo.ci.runs.first { !$0.status.isActive }!
        watcher.watch(finished, in: "/repo", repository: repo)
        #expect(watcher.watched.isEmpty)

        let run = activeRun(in: repo)
        watcher.watch(run, in: "/repo", repository: repo)
        watcher.stopWatching(run.id, in: "/repo")
        finish(run.id, .success, in: repo)
        await watcher.poll()

        #expect(notifier.notified.isEmpty)
    }

    @Test func aRunDeletedOnTheHostIsDropped() async {
        let repo = MockGitRepository()
        let watcher = watcher
        let run = activeRun(in: repo)
        watcher.watch(run, in: "/repo", repository: repo)
        repo.ci.runs.removeAll { $0.id == run.id }

        await watcher.poll()

        #expect(watcher.watched.isEmpty && notifier.notified.isEmpty)
    }

    @Test func theActionsTabAnnouncesAFinishItSees() async {
        let repo = MockGitRepository()
        let watcher = watcher
        let vm = CIViewModel(repository: repo, watcher: watcher)
        await vm.refresh()
        let run = activeRun(in: repo)
        vm.toggleNotification(for: run)
        #expect(vm.isWatching(run))

        finish(run.id, .success, in: repo)
        await vm.refresh()

        #expect(notifier.notified.map(\.run.id) == [run.id] && !vm.isWatching(run))
    }

    @Test func aDispatchedRunIsWatchedOnceTheHostListsIt() async throws {
        let repo = MockGitRepository()
        let watcher = watcher
        let vm = CIViewModel(repository: repo, watcher: watcher)
        await vm.refresh()
        await vm.setWorkflowFilter(2)
        vm.beginDispatch()
        let sheet = try #require(vm.dispatch)
        await sheet.load()
        sheet.setValue("1.4.0", for: try #require(sheet.inputs.first { $0.name == "version" }))
        sheet.setNotifiesWhenFinished(true)
        defer { sheet.setNotifiesWhenFinished(false) }

        await sheet.submit()

        let started = repo.ci.runs[0]
        #expect(started.event == "workflow_dispatch" && watcher.isWatching(started.id, in: vm.repositoryPath))
        #expect(!watcher.isAwaitingDispatch(in: vm.repositoryPath))

        finish(started.id, .success, in: repo)
        await watcher.poll()
        #expect(notifier.notified.map(\.run.id) == [started.id])
    }

    @Test func aDispatchIsFoundByTheWatcherAloneWhenTheTabIsGone() async {
        let repo = MockGitRepository()
        let watcher = watcher
        let dispatch = CIDispatch(workflowID: MockData.ciWorkflows[0].id, ref: "main")
        watcher.watchDispatch(dispatch, known: Set(repo.ci.runs.map(\.id)), in: "/repo", repository: repo)
        try? await repo.dispatchCIWorkflow(dispatch)

        await watcher.poll()

        #expect(watcher.isWatching(repo.ci.runs[0].id, in: "/repo") && !watcher.isAwaitingDispatch(in: "/repo"))
    }

    @Test func aClickedNotificationWaitsForTheRepositoryToOpen() {
        let watcher = watcher
        var revealed: [Int] = []
        watcher.reveal(runID: 7, in: "/repo")
        watcher.setRevealHandler(for: "/repo") { revealed.append($0) }
        watcher.reveal(runID: 8, in: "/repo")

        #expect(revealed == [7, 8])
    }

    @Test func outcomesReadAsSentences() {
        #expect(SystemCIRunNotifier.outcome(.success) == "passed")
        #expect(SystemCIRunNotifier.outcome(.failure) == "failed")
        #expect(SystemCIRunNotifier.outcome(.cancelled) == "was cancelled")
    }
}
