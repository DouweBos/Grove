// Utilities/Logging.swift
// Grove
//
// Central `os.Logger` configuration for the entire app.
// Every subsystem gets its own named logger so log streams can be
// filtered independently in Console.app or `log stream`.
//
// Usage:
//   Logger.gitShell.debug("Running: git \(args.joined(separator: " "))")

import os

// MARK: - RepositoryState logging support

extension RepositoryState {
    /// A short, human-readable description used in log messages.
    var logDescription: String {
        switch self {
        case .normal:            return "normal"
        case .merge:             return "merge"
        case .rebase:            return "rebase"
        case .rebaseInteractive: return "rebase-interactive"
        case .revert:            return "revert"
        case .cherrypick:        return "cherry-pick"
        case .bisect:            return "bisect"
        }
    }
}

// MARK: - Loggers

extension Logger {
    /// Subsystem used for every Grove logger.
    private static let subsystem = "dev.houwert.grove"

    /// Logs raw git CLI invocations and their results.
    static let gitShell = Logger(subsystem: subsystem, category: "GitShell")

    /// Logs high-level git operations (commit, push, pull, etc.).
    static let gitRepository = Logger(subsystem: subsystem, category: "GitRepository")

    /// Logs bookmark and group management events.
    static let repositoryManager = Logger(subsystem: subsystem, category: "RepositoryManager")

    /// Logs FSEvents watcher lifecycle and filesystem change notifications.
    static let fileWatcher = Logger(subsystem: subsystem, category: "FileWatcher")

    /// Logs UI-layer events such as window open/close and navigation.
    static let ui = Logger(subsystem: subsystem, category: "UI")

    /// Logs parsing events for git output (log, status, diff, etc.).
    static let parsers = Logger(subsystem: subsystem, category: "Parsers")
}
