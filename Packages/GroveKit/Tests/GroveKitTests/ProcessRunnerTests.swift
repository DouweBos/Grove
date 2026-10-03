// ProcessRunnerTests.swift
// GroveKitTests
//
// Output bigger than a pipe buffer on both streams must not stall the child or the reader.

import Foundation
import Testing
@testable import GroveKit

struct ProcessRunnerTests {

    @Test func largeStdoutAndStderrTogetherDoNotDeadlock() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "head -c 200000 /dev/zero | tr '\\\\0' a >&2; head -c 200000 /dev/zero | tr '\\\\0' b; exit 3"]
        let output = try await ProcessRunner.run(process)
        #expect(output.stdout.count == 200_000)
        #expect(output.stderr.count == 200_000)
        #expect(output.status == 3)
    }

    @Test func largeInputIsFedWhileOutputIsRead() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        let input = Data(repeating: 0x61, count: 300_000)
        let output = try await ProcessRunner.run(process, input: input)
        #expect(output.stdout == input)
        #expect(output.status == 0)
    }
}
