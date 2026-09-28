// Models/RebasePlan.swift
// Grove

import Foundation

/// What an interactive rebase does with one commit; raw values are the todo-list verbs.
enum RebaseAction: String, CaseIterable, Identifiable, Sendable {
    case pick, reword, squash, fixup, drop

    var id: Self { self }

    var title: String { rawValue.capitalized }

    /// Squash and fixup fold into the commit before them, so they need one to fold into.
    var foldsIntoPrevious: Bool { self == .squash || self == .fixup }
}

/// One line of an interactive rebase plan.
struct RebaseStep: Identifiable, Hashable, Sendable {
    let sha: String
    var action: RebaseAction = .pick
    /// The new message for a reword.
    var message: String?

    var id: String { sha }
}

enum RebasePlan {

    /// The todo list git runs, oldest first. Rewords amend right after their pick, so no editor is needed.
    /// `messageFile` maps a reworded SHA to a shell-quoted path holding its new message.
    static func todo(_ steps: [RebaseStep], messageFile: (String) -> String?) -> String {
        // An empty todo makes git abort; noop runs the rebase with nothing kept.
        guard steps.contains(where: { $0.action != .drop }) else { return "noop\n" }
        return steps.compactMap { step -> String? in
            switch step.action {
            case .drop:
                return nil
            case .reword:
                guard let file = messageFile(step.sha) else { return "pick \(step.sha)" }
                return "pick \(step.sha)\nexec git commit --amend --no-verify --allow-empty -q -F \(file)"
            case .pick, .squash, .fixup:
                return "\(step.action.rawValue) \(step.sha)"
            }
        }
        .joined(separator: "\n") + "\n"
    }

    /// Why a plan can't run, or nil when it can.
    static func problem(with steps: [RebaseStep]) -> String? {
        let kept = steps.filter { $0.action != .drop }
        if let first = kept.first, first.action.foldsIntoPrevious {
            return "The first commit can't be squashed or fixed up; there's nothing before it to fold into."
        }
        if steps.contains(where: { $0.action == .reword && ($0.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return "Reworded commits need a message."
        }
        return nil
    }
}
