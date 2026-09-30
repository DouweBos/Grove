// Views/CI/CIViewModel+Polling.swift
// Grove

import Foundation

extension CIViewModel {

    /// Polls for as long as the calling task lives, i.e. while the Actions tab is on screen.
    /// `sleep` is injected so tests don't wait; throwing from it ends the loop.
    func pollWhileVisible(sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) async {
        while !Task.isCancelled {
            let interval = pollInterval
            let wait = Task { try await sleep(interval) }
            pollWait = wait
            let outcome = await withTaskCancellationHandler { await wait.result } onCancel: { wait.cancel() }
            pollWait = nil
            let woken = isWakingPoll
            isWakingPoll = false
            if case .failure = outcome, !woken { return }
            if Task.isCancelled { return }
            await poll()
        }
    }

    /// Cuts the current wait short, e.g. after starting a run.
    func pollNow() {
        guard let pollWait else { return }
        isWakingPoll = true
        pollWait.cancel()
    }
}
