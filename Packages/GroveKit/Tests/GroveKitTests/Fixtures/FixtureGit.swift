// FixtureGit.swift
// GroveKitTests
//
// Runs git for the fixture generator, isolated from the user's global and system config.

import Foundation

enum FixtureGit {

    /// No ~/.gitconfig or system config, so hooks, signing or fsmonitor settings can't leak into fixtures.
    static let environment: [String: String] = {
        var env = ProcessInfo.processInfo.environment
        env["GIT_CONFIG_GLOBAL"] = "/dev/null"
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["GIT_EDITOR"] = "true"
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        env["GIT_AUTHOR_NAME"] = "Fixture Bot"
        env["GIT_AUTHOR_EMAIL"] = "fixture@example.com"
        env["GIT_COMMITTER_NAME"] = "Fixture Bot"
        env["GIT_COMMITTER_EMAIL"] = "fixture@example.com"
        for key in env.keys where key.hasPrefix("GIT_DIR") || key == "GIT_WORK_TREE" || key == "GIT_INDEX_FILE" {
            env[key] = nil
        }
        return env
    }()

    /// A real git binary: /usr/bin/git is an xcrun shim that adds tens of milliseconds to every call.
    static let gitPath: String = {
        let direct = ["/opt/homebrew/bin/git", "/usr/local/bin/git"].first { FileManager.default.isExecutableFile(atPath: $0) }
        return direct ?? xcrunGit() ?? "/usr/bin/git"
    }()

    private static func xcrunGit() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "git"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let path = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()
        return process.terminationStatus == 0 && !path.isEmpty ? path : nil
    }

    @discardableResult
    static func run(_ arguments: [String], in directory: URL, input: URL? = nil, date: Int? = nil,
                    allowFailure: Bool = false) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gitPath)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        var env = environment
        if let date {
            env["GIT_AUTHOR_DATE"] = "\(date) +0000"
            env["GIT_COMMITTER_DATE"] = "\(date) +0000"
        }
        process.environment = env
        let output = Pipe()
        process.standardOutput = output
        // stderr goes to a file so a chatty command can't fill a pipe we aren't reading yet.
        let errorURL = FileManager.default.temporaryDirectory.appendingPathComponent("fixture-stderr-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: errorURL) }
        process.standardError = try FileHandle(forWritingTo: errorURL)
        if let input { process.standardInput = try FileHandle(forReadingFrom: input) }
        // waitUntilExit polls a run loop and adds ~60 ms per call; the handler fires as soon as git exits.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        exited.wait()
        let text = String(bytes: data, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 && !allowFailure {
            let stderr = (try? String(contentsOf: errorURL, encoding: .utf8)) ?? ""
            throw FixtureError.git(command: arguments.joined(separator: " "), status: process.terminationStatus,
                                   output: stderr + text)
        }
        return text
    }

    /// Commits `files` (path to contents) in `repo` at a fixed date.
    static func commit(_ files: [String: Data], message: String, in repo: URL, date: Int) throws {
        for (path, contents) in files {
            let url = repo.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url)
        }
        try run(["add", "--"] + files.keys.sorted(), in: repo)
        try run(["commit", "-q", "--no-verify", "-m", message], in: repo, date: date)
    }

    static func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map(String.init)
    }
}
