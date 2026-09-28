// Views/History/InteractiveRebaseViewModel.swift
// Grove

import Foundation
import Observation
import SwiftUI

/// The plan being edited in the interactive rebase sheet, listed newest first like History.
@MainActor
@Observable
final class InteractiveRebaseViewModel {
    let base: CommitInfo
    private(set) var steps: [RebaseStep]
    private let commitsByID: [String: CommitInfo]
    private let initialOrder: [String]

    /// `commits` are the ones above `base`, newest first.
    init(base: CommitInfo, commits: [CommitInfo]) {
        self.base = base
        steps = commits.map { RebaseStep(sha: $0.id) }
        initialOrder = commits.map(\.id)
        commitsByID = Dictionary(commits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func commit(for step: RebaseStep) -> CommitInfo? {
        commitsByID[step.sha]
    }

    func setAction(_ action: RebaseAction, for step: RebaseStep) {
        guard let index = steps.firstIndex(where: { $0.id == step.id }) else { return }
        steps[index].action = action
        if action == .reword, steps[index].message == nil {
            steps[index].message = commitsByID[step.sha]?.message
        }
    }

    func setMessage(_ message: String, for step: RebaseStep) {
        guard let index = steps.firstIndex(where: { $0.id == step.id }) else { return }
        steps[index].message = message
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        steps.move(fromOffsets: source, toOffset: destination)
    }

    /// The plan in the order git runs it, oldest first.
    var plan: [RebaseStep] { steps.reversed() }

    var problem: String? { RebasePlan.problem(with: plan) }

    var isUnchanged: Bool {
        steps.allSatisfy { $0.action == .pick } && steps.map(\.sha) == initialOrder
    }

    var summary: String {
        let counts = Dictionary(grouping: steps, by: \.action).mapValues(\.count)
        let parts = RebaseAction.allCases.compactMap { action in counts[action].map { "\($0) \(action.rawValue)" } }
        return parts.joined(separator: " · ")
    }
}
