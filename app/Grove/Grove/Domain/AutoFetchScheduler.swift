// Domain/AutoFetchScheduler.swift
// Grove
//
// Periodically fetches all remotes for an open repository.
// Owned by RepositorySession and started/stopped with the window lifecycle.

import Foundation
import Observation
import os

// MARK: - AutoFetchScheduler

/// Schedules background fetches for a repository at a configurable interval.
///
/// Wire it into a view's lifecycle:
/// ```swift
/// .task { autoFetcher.start() }
/// .onDisappear { autoFetcher.stop() }
/// ```
///
/// Set `intervalMinutes` to `0` to disable automatic fetching while still
/// allowing manual triggers via ``fetchNow()``.
@MainActor
@Observable
final class AutoFetchScheduler {

    // MARK: - Configuration

    /// How often to fetch, in minutes. `0` disables automatic fetching.
    ///
    /// Initialized from the `autoFetchMinutes` key in `UserDefaults` so that
    /// the preference set in General Preferences takes effect automatically.
    var intervalMinutes: Int = UserDefaults.standard.integer(forKey: "autoFetchMinutes") {
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
    private var isStarted: Bool = false
    private let repository: any GitRepositoryProtocol

    // MARK: - Init

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: - Lifecycle

    /// Starts the periodic fetch timer using the current ``intervalMinutes``.
    ///
    /// Calling `start()` when the scheduler is already running restarts the timer.
    func start() {
        isStarted = true
        scheduleTimer()
        Logger.ui.info("AutoFetchScheduler: started (interval=\(self.intervalMinutes, privacy: .public) min) for \(self.repository.displayName, privacy: .public)")
    }

    /// Cancels the periodic fetch timer.
    ///
    /// An in-progress fetch is allowed to complete naturally.
    func stop() {
        isStarted = false
        cancelTimer()
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
                await self?.performFetch()
            }
        }
        // Add to .common so the timer fires even when the run loop is busy
        // (e.g. during menu tracking).
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
        Logger.ui.debug("AutoFetchScheduler: timer scheduled every \(self.intervalMinutes, privacy: .public) minute(s)")
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func restartIfRunning() {
        guard isStarted else { return }
        scheduleTimer()
    }

    private func performFetch() async {
        guard !isFetching else { return }
        isFetching = true
        lastFetchError = nil
        Logger.ui.info("AutoFetchScheduler: fetching remotes for \(self.repository.displayName, privacy: .public)")

        do {
            try await repository.fetch(remote: nil, progress: nil)
            lastFetchDate = Date()
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
