// Domain/CI/CIRunWatcher.swift
// Grove
//
// Runs someone asked to hear about, polled until they finish and then announced with a notification.

import Foundation
import Observation

/// Shows the "run finished" notification; a protocol so tests can read what would have been shown.
@MainActor
protocol CIRunNotifying: AnyObject {
    func requestAuthorization() async
    func notify(_ run: CIRun, repositoryPath: String)
}

/// App-wide, so a watched run is still announced after its tab, window or session is gone.
@MainActor
@Observable
final class CIRunWatcher {

    static let shared = CIRunWatcher(notifier: SystemCIRunNotifier())

    struct Watch: Hashable {
        let repositoryPath: String
        let runID: Int
    }

    /// A started workflow whose run the host hasn't listed yet.
    private struct AwaitedDispatch {
        let id = UUID()
        let repositoryPath: String
        let repository: any GitRepositoryProtocol
        let dispatch: CIDispatch
        let known: Set<Int>
        let startedDate: Date
    }

    /// How long a dispatched run may take to show up before it's given up on.
    static let dispatchTimeout: TimeInterval = 300

    private(set) var watched: Set<Watch> = []
    @ObservationIgnored private var repositories: [Watch: any GitRepositoryProtocol] = [:]
    @ObservationIgnored private var awaitedDispatches: [AwaitedDispatch] = []
    @ObservationIgnored private var watchingSince: Date?
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var loop: Task<Void, Never>?
    /// Per open repository, set by its session: shows a run when its notification is clicked.
    @ObservationIgnored private var revealHandlers: [String: (Int) -> Void] = [:]
    @ObservationIgnored private var pendingReveals: [String: Int] = [:]

    let notifier: any CIRunNotifying
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    /// `sleep` is injected so tests don't wait; throwing from it ends the poll loop.
    init(notifier: any CIRunNotifying,
         sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.notifier = notifier
        self.sleep = sleep
    }

    // MARK: - Watching

    func isWatching(_ runID: Int, in repositoryPath: String) -> Bool {
        watched.contains(Watch(repositoryPath: repositoryPath, runID: runID))
    }

    func isAwaitingDispatch(in repositoryPath: String) -> Bool {
        awaitedDispatches.contains { $0.repositoryPath == repositoryPath }
    }

    func watch(_ run: CIRun, in repositoryPath: String, repository: any GitRepositoryProtocol) {
        guard run.status.isActive else { return }
        let watch = Watch(repositoryPath: repositoryPath, runID: run.id)
        repositories[watch] = repository
        watched.insert(watch)
        start()
    }

    func stopWatching(_ runID: Int, in repositoryPath: String) {
        let watch = Watch(repositoryPath: repositoryPath, runID: runID)
        repositories[watch] = nil
        watched.remove(watch)
    }

    /// The host doesn't say which run a dispatch became, so the first new manual run of that workflow and ref is taken to be it.
    func watchDispatch(_ dispatch: CIDispatch, known: Set<Int>, in repositoryPath: String, repository: any GitRepositoryProtocol) {
        awaitedDispatches.append(AwaitedDispatch(repositoryPath: repositoryPath, repository: repository, dispatch: dispatch,
                                                 known: known, startedDate: Date()))
        start()
    }

    /// Runs read elsewhere, e.g. by the Actions tab's own polls, so a finish it sees is announced at once.
    func observe(_ runs: [CIRun], in repositoryPath: String) {
        for awaited in awaitedDispatches where awaited.repositoryPath == repositoryPath {
            guard let started = runs.first(where: { matches($0, awaited) }) else { continue }
            awaitedDispatches.removeAll { $0.id == awaited.id }
            let watch = Watch(repositoryPath: repositoryPath, runID: started.id)
            repositories[watch] = awaited.repository
            watched.insert(watch)
        }
        for run in runs where !run.status.isActive && isWatching(run.id, in: repositoryPath) {
            stopWatching(run.id, in: repositoryPath)
            notifier.notify(run, repositoryPath: repositoryPath)
        }
    }

    private func matches(_ run: CIRun, _ awaited: AwaitedDispatch) -> Bool {
        // A little slack for the host's clock running behind this Mac's.
        run.workflowID == awaited.dispatch.workflowID && run.event == "workflow_dispatch" && run.branch == awaited.dispatch.ref
            && !awaited.known.contains(run.id) && run.createdDate > awaited.startedDate.addingTimeInterval(-60)
    }

    // MARK: - Polling

    private var hasWork: Bool { !watched.isEmpty || !awaitedDispatches.isEmpty }

    private func start() {
        if watchingSince == nil { watchingSince = Date() }
        guard loop == nil else { return }
        Task { await notifier.requestAuthorization() }
        loop = Task { [weak self] in
            while let self, self.hasWork, !Task.isCancelled {
                let interval = CIPollSchedule.interval(activeFor: self.watchingSince.map { Date().timeIntervalSince($0) },
                                                       consecutiveFailures: self.consecutiveFailures)
                do { try await self.sleep(interval) } catch { break }
                await self.poll()
            }
            self?.loop = nil
            self?.watchingSince = nil
        }
    }

    /// Reads each watched run, and looks for the runs of workflows just started.
    func poll() async {
        var failed = false
        for (watch, repository) in repositories {
            do {
                observe([try await repository.ciRun(id: watch.runID)], in: watch.repositoryPath)
            } catch HostingError.http(status: 404, _) {
                stopWatching(watch.runID, in: watch.repositoryPath)
            } catch {
                failed = true
            }
        }
        awaitedDispatches.removeAll { Date().timeIntervalSince($0.startedDate) > Self.dispatchTimeout }
        for awaited in awaitedDispatches {
            let query = CIRunQuery(workflowID: awaited.dispatch.workflowID, branch: awaited.dispatch.ref).limited(to: 10)
            do {
                observe(try await awaited.repository.ciRuns(query), in: awaited.repositoryPath)
            } catch {
                failed = true
            }
        }
        consecutiveFailures = failed ? consecutiveFailures + 1 : 0
    }

    // MARK: - Revealing

    func setRevealHandler(for repositoryPath: String, _ handler: @escaping (Int) -> Void) {
        revealHandlers[repositoryPath] = handler
        if let runID = pendingReveals.removeValue(forKey: repositoryPath) { handler(runID) }
    }

    /// A clicked notification: brings the repository up and selects the run, once its session is there.
    func reveal(runID: Int, in repositoryPath: String) {
        RepositoryURLRouter.openHandler?(repositoryPath)
        if let handler = revealHandlers[repositoryPath] { handler(runID) } else { pendingReveals[repositoryPath] = runID }
    }
}
