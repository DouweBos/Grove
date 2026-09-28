// Domain/CloneQueue.swift
// Grove
//
// Clones running in the background, so the window stays usable and several can run at once.

import Foundation
import Observation
import os

@MainActor
@Observable
final class CloneQueue {

    struct Job: Identifiable, Equatable {
        enum State: Equatable {
            case running
            case failed(String)
        }

        let id = UUID()
        let url: String
        let destination: URL
        var state: State = .running
        var progress: CloneProgress?

        var name: String { destination.lastPathComponent }
        /// `host/owner/name`, to show progress on the matching row of the remote browser.
        var matchKey: String? { RemoteURLKey.make(url) }
        var isRunning: Bool { state == .running }
    }

    private(set) var jobs: [Job] = []
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]

    let manager: any RepositoryManagerProtocol
    /// Called with the new repository's path once its clone is bookmarked.
    @ObservationIgnored var onFinished: ((String) -> Void)?

    init(manager: any RepositoryManagerProtocol) {
        self.manager = manager
    }

    var runningCount: Int { jobs.filter(\.isRunning).count }

    func job(matching key: String?) -> Job? {
        guard let key else { return nil }
        return jobs.first { $0.matchKey == key }
    }

    /// Why `destination` can't take a new clone, or nil when it can.
    func problem(cloning url: String, to destination: URL) -> String? {
        if jobs.contains(where: { $0.destination.standardizedFileURL == destination.standardizedFileURL }) {
            return "\(destination.lastPathComponent) is already being cloned there."
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            return "\(abbreviatingHome(destination.path)) already exists. Pick another name or location."
        }
        return nil
    }

    /// Starts a clone; returns false when `problem(cloning:to:)` has a reason not to.
    @discardableResult
    func start(url: String, destination: URL) -> Bool {
        guard problem(cloning: url, to: destination) == nil else { return false }
        let job = Job(url: url, destination: destination)
        jobs.append(job)
        run(job.id)
        return true
    }

    func retry(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), !jobs[index].isRunning else { return }
        jobs[index].state = .running
        jobs[index].progress = nil
        run(id)
    }

    /// Stops a running clone (git removes what it had written) or clears a failed one.
    func cancel(_ id: UUID) {
        tasks[id]?.cancel()
        tasks[id] = nil
        jobs.removeAll { $0.id == id }
    }

    private func run(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        let (url, destination, manager) = (job.url, job.destination, manager)
        tasks[id] = Task { [weak self] in
            do {
                _ = try await manager.cloneRepository(url: url, to: destination) { progress in
                    Task { @MainActor in self?.update(id) { $0.progress = progress } }
                }
                self?.finish(id, path: destination.path)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                Logger.repositoryManager.error("Background clone failed: \(error.localizedDescription, privacy: .public)")
                self?.update(id) { $0.state = .failed(error.localizedDescription) }
                self?.tasks[id] = nil
            }
        }
    }

    private func finish(_ id: UUID, path: String) {
        jobs.removeAll { $0.id == id }
        tasks[id] = nil
        onFinished?(path)
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }
}
