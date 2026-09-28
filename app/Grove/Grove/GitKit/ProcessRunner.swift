// GitKit/ProcessRunner.swift
// Grove
//
// Runs a child process off the main actor and collects its output.

import Foundation

nonisolated enum ProcessRunner {

    struct Output: Sendable {
        let stdout: Data
        let stderr: Data
        let status: Int32
    }

    /// Runs `process` on a background queue, draining stdout and stderr at the same time (a full
    /// 64 KB pipe would otherwise stall the child) and waking on its termination handler rather
    /// than `waitUntilExit`, which polls. Callers on the main actor only suspend.
    static func run(_ process: Process, input: Data? = nil) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try runBlocking(process, input: input))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(_ process: Process, input: Data?) throws -> Output {
        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = input.map { _ in Pipe() }
        process.standardOutput = stdout
        process.standardError = stderr
        if let stdin { process.standardInput = stdin }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()

        let readers = DispatchGroup()
        let errorOutput = DataBox()
        DispatchQueue.global(qos: .userInitiated).async(group: readers) {
            errorOutput.data = stderr.fileHandleForReading.readDataToEndOfFile()
        }
        if let input, let stdin {
            DispatchQueue.global(qos: .userInitiated).async(group: readers) {
                stdin.fileHandleForWriting.write(input)
                try? stdin.fileHandleForWriting.close()
            }
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        readers.wait()
        exited.wait()
        return Output(stdout: output, stderr: errorOutput.data, status: process.terminationStatus)
    }

    /// Written by exactly one reader before `readers.wait()` returns, so no lock is needed.
    private final class DataBox: @unchecked Sendable {
        var data = Data()
    }
}
