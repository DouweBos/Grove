// Dialogs/Template/DialogOperation.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import Foundation
import Observation

/// What a dialog is running: its title and progress for the sheet, the error it ended with, and a task Cancel can stop.
@Observable @MainActor
final class DialogOperation {
    private(set) var title: String?
    /// 0–1 as git reports it; nil until it does.
    private(set) var fraction: Double?
    var errorMessage: String?
    private var task: Task<Void, Never>?

    var isRunning: Bool { title != nil }

    /// Runs `work`; `completion` gets true when it worked, false when it failed and nil when it was cancelled.
    func run(_ title: String, _ work: @escaping (_ progress: @escaping @Sendable (Double) -> Void) async throws -> Void,
             completion: @escaping (Bool?) async -> Void) {
        guard !isRunning else { return }
        self.title = title
        fraction = nil
        errorMessage = nil
        let progress: @Sendable (Double) -> Void = { value in
            Task { @MainActor in self.advance(to: value) }
        }
        task = Task {
            let outcome: Bool?
            do {
                try await work(progress)
                outcome = true
            } catch is CancellationError {
                outcome = nil
            } catch {
                if Task.isCancelled {
                    outcome = nil
                } else {
                    errorMessage = error.localizedDescription
                    outcome = false
                }
            }
            self.title = nil
            await completion(outcome)
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func advance(to value: Double) {
        guard isRunning else { return }
        fraction = max(fraction ?? 0, value)
    }
}
#endif
