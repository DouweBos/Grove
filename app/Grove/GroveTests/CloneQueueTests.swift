// CloneQueueTests.swift
// GroveTests

import Foundation
import Testing
@testable import Grove

@MainActor
struct CloneQueueTests {

    private func destination(_ name: String = "app") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("grove-clone-\(UUID().uuidString)/\(name)")
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(nanoseconds: 10_000_000) }
    }

    // MARK: Parsing

    @Test func parsesTheLastProgressLineOfAChunk() {
        let chunk = "Receiving objects:  44% (440/1000)\rReceiving objects:  45% (450/1000), 1.20 MiB | 2.00 MiB/s\r"
        let progress = CloneProgressParser.parse(chunk)
        #expect(progress?.phase == .fetching && progress?.receivedObjects == 450 && progress?.totalObjects == 1000)
        #expect(abs((progress?.overallFraction ?? 0) - 0.3375) < 0.0001)
        #expect(CloneProgressParser.parse("Resolving deltas: 100% (80/80), done.\n")?.phase == .indexing)
        #expect(CloneProgressParser.parse("Updating files:  10% (1/10)\r")?.overallFraction == 0.91)
        #expect(CloneProgressParser.parse("Cloning into 'app'...\n") == nil)
    }

    @Test func errorsDropTheProgressNoise() {
        let stderr = "Cloning into 'x'...\nremote: Enumerating objects: 5\rReceiving objects:  20% (1/5)\r"
            + "fatal: repository 'https://example.com/x.git/' not found\n"
        #expect(CloneProgressParser.errorMessage(from: stderr) == "fatal: repository 'https://example.com/x.git/' not found")
        #expect(CloneProgressParser.errorMessage(from: "") == "git clone failed.")
    }

    // MARK: Queue

    @Test func severalClonesRunAndBookmarkWhenDone() async throws {
        let manager = MockRepositoryManager()
        manager.cloneStepDelay = 5_000_000
        let queue = CloneQueue(manager: manager)
        var finished: [String] = []
        queue.onFinished = { finished.append($0) }
        let first = destination("one"), second = destination("two")
        #expect(queue.start(url: "git@github.com:example/one.git", destination: first))
        #expect(queue.start(url: "git@github.com:example/two.git", destination: second))
        #expect(queue.runningCount == 2)
        #expect(queue.job(matching: "github.com/example/one")?.name == "one")
        try await waitUntil { queue.jobs.isEmpty }
        #expect(Set(finished) == [first.path, second.path])
        #expect(manager.bookmarks.contains { $0.path == second.path })
    }

    @Test func failureStaysOnTheRowAndRetryRunsAgain() async throws {
        let manager = MockRepositoryManager()
        manager.cloneStepDelay = 5_000_000
        manager.cloneFailure = "fatal: repository not found"
        let queue = CloneQueue(manager: manager)
        queue.start(url: "https://example.com/missing.git", destination: destination())
        try await waitUntil { queue.jobs.first?.isRunning == false }
        #expect(queue.jobs.first?.state == .failed("fatal: repository not found"))
        manager.cloneFailure = nil
        queue.retry(try #require(queue.jobs.first).id)
        #expect(queue.jobs.first?.isRunning == true)
        try await waitUntil { queue.jobs.isEmpty }
        #expect(queue.jobs.isEmpty)
    }

    @Test func cancelStopsTheClone() async throws {
        let manager = MockRepositoryManager()
        let queue = CloneQueue(manager: manager)
        let target = destination()
        queue.start(url: "https://example.com/big.git", destination: target)
        queue.cancel(try #require(queue.jobs.first).id)
        #expect(queue.jobs.isEmpty)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!manager.bookmarks.contains { $0.path == target.path })
    }

    @Test func refusesTakenDestinations() throws {
        let queue = CloneQueue(manager: MockRepositoryManager())
        let existing = FileManager.default.temporaryDirectory
        #expect(queue.problem(cloning: "x", to: existing) != nil)
        #expect(!queue.start(url: "x", destination: existing))
        let fresh = destination()
        #expect(queue.start(url: "x", destination: fresh))
        #expect(queue.problem(cloning: "y", to: fresh)?.contains("already being cloned") == true)
    }
}
