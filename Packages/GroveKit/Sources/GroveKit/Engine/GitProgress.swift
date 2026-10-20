// Engine/GitProgress.swift
// GroveKit
//
// Turns the `--progress` lines fetch, pull and push write to stderr into one fraction for a progress bar.

import Foundation
import os

/// One phase of git's transfer progress, with how far it is.
nonisolated struct GitProgress: Equatable {

    enum Phase: CaseIterable {
        case compressing, writing, receiving, unpacking, resolving, updatingFiles, filtering

        var label: String {
            switch self {
            case .compressing: "Compressing objects"
            case .writing: "Writing objects"
            case .receiving: "Receiving objects"
            case .unpacking: "Unpacking objects"
            case .resolving: "Resolving deltas"
            case .updatingFiles: "Updating files"
            case .filtering: "Filtering content"
            }
        }

        /// Where the phase sits in the whole command: push writes, fetch receives, pull then updates the worktree.
        var span: ClosedRange<Double> {
            switch self {
            case .compressing: 0...0.1
            case .writing: 0.1...1
            case .receiving, .unpacking: 0...0.6
            case .resolving: 0.6...0.7
            case .updatingFiles: 0.7...0.85
            case .filtering: 0.85...1
            }
        }
    }

    let phase: Phase
    /// 0–1 within the phase.
    let fraction: Double

    /// 0–1 across the whole command.
    var overall: Double { phase.span.lowerBound + fraction * (phase.span.upperBound - phase.span.lowerBound) }

    /// The last progress line in a chunk of stderr, e.g. `Receiving objects:  45% (450/1000), 1.20 MiB | 2.00 MiB/s`.
    /// Lines are separated by `\r` while they update.
    static func parse(_ chunk: String) -> GitProgress? {
        for line in chunk.split(whereSeparator: { $0 == "\r" || $0 == "\n" }).reversed() {
            if let progress = progress(in: line) { return progress }
        }
        return nil
    }

    private static func progress(in line: Substring) -> GitProgress? {
        guard let phase = Phase.allCases.first(where: { line.contains($0.label) }),
              let percent = line.firstIndex(of: "%") else { return nil }
        let digits = line[..<percent].reversed().prefix { $0.isNumber }
        guard let value = Double(String(digits.reversed())) else { return nil }
        return GitProgress(phase: phase, fraction: min(value, 100) / 100)
    }
}

/// Reports a command's progress into `range` of the caller's bar, never moving backwards:
/// submodules and LFS restart git's phases, which shouldn't rewind the bar.
nonisolated final class GitProgressReporter: Sendable {
    private let range: ClosedRange<Double>
    private let report: @Sendable (Double) -> Void
    private let highest = OSAllocatedUnfairLock(initialState: 0.0)

    init(range: ClosedRange<Double> = 0...1, report: @escaping @Sendable (Double) -> Void) {
        self.range = range
        self.report = report
    }

    func consume(_ chunk: String) {
        guard let progress = GitProgress.parse(chunk) else { return }
        let value = range.lowerBound + progress.overall * (range.upperBound - range.lowerBound)
        let advanced = highest.withLock { highest in
            guard value > highest else { return false }
            highest = value
            return true
        }
        if advanced { report(value) }
    }
}
