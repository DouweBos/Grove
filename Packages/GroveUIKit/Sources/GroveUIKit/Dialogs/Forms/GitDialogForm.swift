// Dialogs/Forms/GitDialogForm.swift
// GroveUIKit
//
// What each dialog submits, apart from its sheet, so an app can test it or run it without one.

#if os(macOS)
import Foundation
import GroveKit

public protocol GitDialogForm {
    /// What submitting runs, in order, before anything it reads at the time (e.g. whether to stash first).
    var commands: [GitCommand] { get }
    /// Runs the form through `context.commands`.
    func submit(in context: GitDialogContext, progress: (@Sendable (Double) -> Void)?) async throws
}

extension GitDialogForm {
    public func submit(in context: GitDialogContext, progress: (@Sendable (Double) -> Void)?) async throws {
        try requireSupport(in: context)
        try await perform(commands, in: context, progress: progress)
    }

    /// Throws before anything runs when one of the commands isn't supported.
    func requireSupport(in context: GitDialogContext) throws {
        for command in commands { try context.commands.requireSupport(for: command) }
    }

    /// Why the repository can't run this form, or nil when it can.
    public func unsupportedReason(_ features: GitFeatures) -> String? {
        for command in commands {
            if let missing = GitFeature.allCases.first(where: { command.requiredFeatures.contains($0) && !features.contains($0) }) {
                return features.unavailableReason(missing)
            }
        }
        return nil
    }

    /// The last command gets the progress; the ones before it are quick.
    func perform(_ commands: [GitCommand], in context: GitDialogContext, progress: (@Sendable (Double) -> Void)?) async throws {
        for (index, command) in commands.enumerated() {
            try await context.commands.perform(command, progress: index == commands.count - 1 ? progress : nil)
        }
    }

    /// Stashes everything uncommitted, returning whether there was anything, so callers never pop an older stash.
    func stashIfDirty(_ context: GitDialogContext, message: String) async throws -> Bool {
        let dirty = try await context.repository.status().contains {
            $0.indexStatus != .unmodified || $0.workdirStatus != .unmodified
        }
        if dirty {
            try await context.commands.perform(.stash(message: message, includeUntracked: true, keepIndex: false, paths: nil))
        }
        return dirty
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
#endif
