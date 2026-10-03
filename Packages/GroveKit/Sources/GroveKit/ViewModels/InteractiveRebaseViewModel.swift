// ViewModels/InteractiveRebaseViewModel.swift
// GroveKit

import Foundation
import Observation

/// The plan being edited in the interactive rebase sheet, listed newest first like History.
@MainActor
@Observable
public final class InteractiveRebaseViewModel {
    public let base: CommitInfo
    public private(set) var steps: [RebaseStep]
    private let commitsByID: [String: CommitInfo]
    private let initialOrder: [String]

    /// `commits` are the ones above `base`, newest first.
    public init(base: CommitInfo, commits: [CommitInfo]) {
        self.base = base
        steps = commits.map { RebaseStep(sha: $0.id) }
        initialOrder = commits.map(\.id)
        commitsByID = Dictionary(commits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func commit(for step: RebaseStep) -> CommitInfo? {
        commitsByID[step.sha]
    }

    public func setAction(_ action: RebaseAction, for step: RebaseStep) {
        guard let index = steps.firstIndex(where: { $0.id == step.id }) else { return }
        steps[index].action = action
        if action == .reword, steps[index].message == nil {
            steps[index].message = commitsByID[step.sha]?.message
        }
    }

    public func setMessage(_ message: String, for step: RebaseStep) {
        guard let index = steps.firstIndex(where: { $0.id == step.id }) else { return }
        steps[index].message = message
    }

    /// Same semantics as SwiftUI's `move(fromOffsets:toOffset:)`, which GroveKit can't import.
    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { steps[$0] }
        var remaining = steps.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let insertAt = destination - source.count(in: 0..<destination)
        remaining.insert(contentsOf: moving, at: insertAt)
        steps = remaining
    }

    /// The plan in the order git runs it, oldest first.
    public var plan: [RebaseStep] { steps.reversed() }

    public var problem: String? { RebasePlan.problem(with: plan) }

    public var isUnchanged: Bool {
        steps.allSatisfy { $0.action == .pick } && steps.map(\.sha) == initialOrder
    }

    public var summary: String {
        let counts = Dictionary(grouping: steps, by: \.action).mapValues(\.count)
        let parts = RebaseAction.allCases.compactMap { action in counts[action].map { "\($0) \(action.rawValue)" } }
        return parts.joined(separator: " · ")
    }
}
