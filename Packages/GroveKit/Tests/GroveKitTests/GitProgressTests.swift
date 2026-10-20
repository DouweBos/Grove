// GitProgressTests.swift
// GroveKitTests

import Foundation
import os
import Testing
@testable import GroveKit

struct GitProgressTests {

    @Test func readsTheLastProgressLineInAChunk() {
        let chunk = "Receiving objects:  10% (1/10)\rReceiving objects:  45% (450/1000), 1.20 MiB | 2.00 MiB/s\r"
        #expect(GitProgress.parse(chunk) == GitProgress(phase: .receiving, fraction: 0.45))
    }

    @Test func ignoresLinesWithoutAKnownPhase() {
        #expect(GitProgress.parse("remote: Enumerating objects: 12, done.\nFrom github.com:a/b\n") == nil)
    }

    @Test func pullPhasesFillTheBarInOrder() {
        let receiving = GitProgress(phase: .receiving, fraction: 1).overall
        let resolving = GitProgress(phase: .resolving, fraction: 1).overall
        let updating = GitProgress(phase: .updatingFiles, fraction: 1).overall
        #expect(receiving < resolving && resolving < updating)
        #expect(GitProgress(phase: .filtering, fraction: 1).overall == 1)
    }

    @Test nonisolated func reporterScalesIntoItsRangeAndNeverRewinds() {
        let reported = OSAllocatedUnfairLock(initialState: [Double]())
        let reporter = GitProgressReporter(range: 0...0.5) { value in reported.withLock { $0.append(value) } }
        reporter.consume("Receiving objects: 100% (10/10)\n")
        // A submodule's fetch starts again from zero.
        reporter.consume("Receiving objects:  20% (2/10)\r")
        reporter.consume("Resolving deltas: 100% (4/4)\n")
        #expect(reported.withLock { $0 } == [0.3, 0.35])
    }
}
