// Engine/Logging.swift
// GroveKit
//
// Named loggers so GroveKit's log streams can be filtered in Console.app or `log stream`.

import os

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

nonisolated extension Logger {
    private static let subsystem = "dev.houwert.grovekit"

    /// Raw git invocations and their results.
    static let gitShell = Logger(subsystem: subsystem, category: "GitShell")
    /// High-level git operations (commit, push, pull, etc.).
    static let gitRepository = Logger(subsystem: subsystem, category: "GitRepository")
    /// FSEvents watcher lifecycle and change notifications.
    static let fileWatcher = Logger(subsystem: subsystem, category: "FileWatcher")
    /// UI-layer events of the view models.
    static let ui = Logger(subsystem: subsystem, category: "UI")
    /// Parsing of git output.
    static let parsers = Logger(subsystem: subsystem, category: "Parsers")
}
