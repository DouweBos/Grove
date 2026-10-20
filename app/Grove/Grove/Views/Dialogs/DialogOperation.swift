// Views/Dialogs/DialogOperation.swift
// Grove

import Foundation

/// A dialog's remote operation: its progress for the sheet's bar, and a task Cancel can stop git through.
@Observable @MainActor
final class DialogOperation {

    private(set) var isRunning = false
    /// 0–1 while running, as git reports it.
    private(set) var fraction: Double = 0
    private var task: Task<Void, Never>?

    /// Runs `work` with a progress callback; `completion` gets nil when the operation was cancelled.
    func run(_ work: @escaping (_ progress: @escaping @Sendable (Double) -> Void) async throws -> Void,
             completion: @escaping (Result<Void, any Error>?) -> Void) {
        isRunning = true
        fraction = 0
        let progress: @Sendable (Double) -> Void = { [weak self] value in
            Task { @MainActor in self?.advance(to: value) }
        }
        task = Task {
            let result: Result<Void, any Error>?
            do {
                try await work(progress)
                result = .success(())
            } catch is CancellationError {
                result = nil
            } catch {
                result = Task.isCancelled ? nil : .failure(error)
            }
            isRunning = false
            completion(result)
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func advance(to value: Double) {
        guard isRunning else { return }
        fraction = max(fraction, value)
    }
}
