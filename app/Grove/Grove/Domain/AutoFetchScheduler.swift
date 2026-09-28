// Domain/AutoFetchScheduler.swift
// Grove
//
// Periodically fetches all remotes for an open repository.
// Owned by RepositorySession; runs from the session's first start until it's evicted.

import Foundation
import Observation
import os

// MARK: - AutoFetchScheduler

/// Schedules background fetches for a repository at a configurable interval.
///
/// Set `intervalMinutes` to `0` to disable automatic fetching while still
/// allowing manual triggers via ``fetchNow()``.
@MainActor
@Observable
final class AutoFetchScheduler {

    // MARK: - Configuration

    /// How often to fetch, in minutes. `0` disables automatic fetching.
    ///
    /// Follows the General preference live while the scheduler is running.
    var intervalMinutes: Int = GrovePreferences.autoFetchMinutes {
        didSet {
            guard oldValue != intervalMinutes else { return }
            // Restart the timer whenever the interval changes so the new
            // value takes effect immediately.
            restartIfRunning()
        }
    }

    // MARK: - Observable State

    /// The date of the last successful fetch, or `nil` if no fetch has run yet.
    private(set) var lastFetchDate: Date?
    /// `true` while a fetch is in progress.
    private(set) var isFetching: Bool = false
    /// Non-nil when the most recent fetch failed.
    private(set) var lastFetchError: String?

    // MARK: - Private

    private var timer: Timer?
    /// Repositories being fetched by any scheduler; two windows on one repository share its fetches.
    private static var fetchingPaths: Set<String> = []
    private static var lastFetched: [String: Date] = [:]
    private(set) var isStarted: Bool = false
    private var preferenceObserver: Task<Void, Never>?
    private let repository: any GitRepositoryProtocol

    // MARK: - Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Lifecycle

    /// Starts the periodic fetch timer using the current ``intervalMinutes``; a running timer keeps its schedule.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        intervalMinutes = GrovePreferences.autoFetchMinutes
        scheduleTimer()
        observePreference()
        Logger.ui.info("AutoFetchScheduler: started (interval=\(self.intervalMinutes, privacy: .public) min) for \(self.repository.displayName, privacy: .public)")
    }

    /// Cancels the periodic fetch timer.
    ///
    /// An in-progress fetch is allowed to complete naturally.
    func stop() {
        isStarted = false
        cancelTimer()
        preferenceObserver?.cancel()
        preferenceObserver = nil
        Logger.ui.info("AutoFetchScheduler: stopped for \(self.repository.displayName, privacy: .public)")
    }

    // MARK: - Manual Trigger

    /// Immediately fetches all remotes, regardless of the scheduled interval.
    ///
    /// Safe to call while a fetch is already running — the second call will
    /// be a no-op if `isFetching` is already `true`.
    func fetchNow() async {
        guard !isFetching else { return }
        await performFetch()
    }

    // MARK: - Private Helpers

    private func scheduleTimer() {
        cancelTimer()
        guard intervalMinutes > 0 else { return }

        let interval = TimeInterval(intervalMinutes * 60)
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                await self?.scheduledFetch(interval: interval)
            }
        }
        // Add to .common so the timer fires even when the run loop is busy
        // (e.g. during menu tracking).
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
        Logger.ui.debug("AutoFetchScheduler: timer scheduled every \(self.intervalMinutes, privacy: .public) minute(s)")
    }

    private func observePreference() {
        preferenceObserver?.cancel()
        preferenceObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                guard let self else { return }
                let minutes = GrovePreferences.autoFetchMinutes
                if minutes != self.intervalMinutes { self.intervalMinutes = minutes }
            }
        }
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func restartIfRunning() {
        guard isStarted else { return }
        scheduleTimer()
    }

    /// Skips a tick when another window's scheduler fetched this repository within the interval.
    private func scheduledFetch(interval: TimeInterval) async {
        let path = repository.path.path
        if let last = Self.lastFetched[path], Date().timeIntervalSince(last) < interval * 0.9 {
            lastFetchDate = last
            return
        }
        await performFetch()
    }

    private func performFetch() async {
        let path = repository.path.path
        guard !isFetching, !Self.fetchingPaths.contains(path) else { return }
        isFetching = true
        Self.fetchingPaths.insert(path)
        defer { Self.fetchingPaths.remove(path) }
        lastFetchError = nil
        Logger.ui.info("AutoFetchScheduler: fetching remotes for \(self.repository.displayName, privacy: .public)")

        do {
            try await repository.fetch(remote: nil, progress: nil)
            lastFetchDate = Date()
            Self.lastFetched[path] = lastFetchDate
            Logger.ui.info("AutoFetchScheduler: fetch succeeded for \(self.repository.displayName, privacy: .public)")
        } catch {
            lastFetchError = error.localizedDescription
            Logger.ui.error("AutoFetchScheduler: fetch failed for \(self.repository.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        isFetching = false
    }
}

// MARK: - Date Formatting Helper

extension AutoFetchScheduler {

    /// A short relative description of ``lastFetchDate`` suitable for the status bar,
    /// e.g. "Fetched remotes just now" or "Fetched remotes 3 min ago".
    var lastFetchRelativeDescription: String? {
        guard let date = lastFetchDate else { return nil }
        let elapsed = Date().timeIntervalSince(date)
        switch elapsed {
        case ..<5:
            return "Fetched remotes just now"
        case ..<60:
            return "Fetched remotes \(Int(elapsed))s ago"
        case ..<3600:
            let mins = Int(elapsed / 60)
            return "Fetched remotes \(mins) min\(mins == 1 ? "" : "s") ago"
        default:
            let hours = Int(elapsed / 3600)
            return "Fetched remotes \(hours) hr\(hours == 1 ? "" : "s") ago"
        }
    }
}
