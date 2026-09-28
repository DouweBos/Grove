// Models/CloneTypes.swift
// Grove
//
// Clone operation progress types.

import Foundation

// MARK: - CloneProgress

/// Progress report emitted during a `git clone` operation.
nonisolated struct CloneProgress: Equatable, Sendable {
    let phase: ClonePhase
    let receivedObjects: Int
    let totalObjects: Int
    let receivedBytes: Int64
    /// Progress fraction of the current phase in [0, 1].
    var fractionCompleted: Double {
        guard totalObjects > 0 else { return 0 }
        return Double(receivedObjects) / Double(totalObjects)
    }

    /// The whole clone in [0, 1]: downloading is most of it, then deltas, then writing files.
    var overallFraction: Double {
        switch phase {
        case .fetching: fractionCompleted * 0.75
        case .indexing: 0.75 + fractionCompleted * 0.15
        case .checkingOut: 0.9 + fractionCompleted * 0.1
        }
    }

    var phaseTitle: String {
        switch phase {
        case .fetching: "Downloading"
        case .indexing: "Resolving"
        case .checkingOut: "Checking out"
        }
    }
}

// MARK: - ClonePhase

/// Phases of a clone operation.
nonisolated enum ClonePhase: Sendable {
    case fetching
    case indexing
    case checkingOut
}

// MARK: - Parsing

nonisolated enum CloneProgressParser {

    /// The last progress line in a chunk of `git clone --progress` stderr, e.g.
    /// `Receiving objects:  45% (450/1000), 1.20 MiB | 2.00 MiB/s`. Lines are separated by `\r` while they update.
    static func parse(_ chunk: String) -> CloneProgress? {
        for line in chunk.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).reversed() {
            if let progress = progress(in: String(line)) { return progress }
        }
        return nil
    }

    private static func progress(in line: String) -> CloneProgress? {
        guard let phase = phase(of: line), let open = line.firstIndex(of: "("), let close = line[open...].firstIndex(of: ")") else { return nil }
        let counts = line[line.index(after: open)..<close].split(separator: "/")
        guard counts.count == 2, let done = Int(counts[0]), let total = Int(counts[1]) else { return nil }
        return CloneProgress(phase: phase, receivedObjects: done, totalObjects: total, receivedBytes: 0)
    }

    private static func phase(of line: String) -> ClonePhase? {
        if line.contains("Receiving objects") { return .fetching }
        if line.contains("Resolving deltas") { return .indexing }
        if line.contains("Updating files") || line.contains("Checking out files") { return .checkingOut }
        return nil
    }

    /// What's left of stderr once progress lines are dropped, e.g. `fatal: repository '…' not found`.
    static func errorMessage(from stderr: String) -> String {
        let lines = stderr.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).map(String.init)
            .filter { !$0.contains("% (") && !$0.hasPrefix("remote: ") && !$0.hasPrefix("Cloning into") }
        let message = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "git clone failed." : message
    }
}

/// A clone git refused, with git's own reason.
nonisolated struct CloneFailure: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}
