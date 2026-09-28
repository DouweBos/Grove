// Domain/GitHubCLI.swift
// Grove
//
// Minimal wrapper around the `gh` CLI for PR data and account status.

import Foundation

enum GitHubCLI {

    enum Failure: LocalizedError {
        case notInstalled
        case notAuthenticated
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled: "The GitHub CLI (gh) is not installed."
            case .notAuthenticated: "The GitHub CLI is not signed in."
            case .failed(let message): message
            }
        }
    }

    struct AuthStatus: Equatable, Sendable {
        var host: String
        var account: String?
        var scopes: String?
    }

    nonisolated static var executablePath: String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    nonisolated static var isInstalled: Bool { executablePath != nil }

    /// Runs `gh` in `directory` and returns stdout; throws a readable failure otherwise.
    nonisolated static func run(_ arguments: [String], in directory: URL? = nil) async throws -> String {
        guard let executable = executablePath else { throw Failure.notInstalled }
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let directory { process.currentDirectoryURL = directory }
            var env = ProcessInfo.processInfo.environment
            env["GH_PROMPT_DISABLED"] = "1"
            env["NO_COLOR"] = "1"
            process.environment = env
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.terminationHandler = { proc in
                let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: stdout)
                } else if stderr.contains("gh auth login") || stderr.contains("not logged") {
                    continuation.resume(throwing: Failure.notAuthenticated)
                } else {
                    let message = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(throwing: Failure.failed(message.isEmpty ? "gh exited with \(proc.terminationStatus)" : message))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: Failure.failed(error.localizedDescription)) }
        }
    }

    /// Accounts `gh` is signed in to; empty when signed out.
    nonisolated static func authStatus() async throws -> [AuthStatus] {
        // `gh auth status` exits 1 when signed out, which surfaces as notAuthenticated.
        let output = try await run(["auth", "status"])
        return parseAuthStatus(output)
    }

    nonisolated static func parseAuthStatus(_ output: String) -> [AuthStatus] {
        var result: [AuthStatus] = []
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if !line.isEmpty, !raw.hasPrefix(" "), !line.hasPrefix("-"), !line.contains(" ") {
                result.append(AuthStatus(host: line))
            } else if let range = line.range(of: "Logged in to "), !result.isEmpty {
                let rest = line[range.upperBound...]
                if let accountRange = rest.range(of: "account ") {
                    result[result.count - 1].account = rest[accountRange.upperBound...]
                        .split(separator: " ").first.map(String.init)
                }
            } else if line.hasPrefix("- Token scopes:"), !result.isEmpty {
                result[result.count - 1].scopes = String(line.dropFirst("- Token scopes:".count))
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "'", with: "")
            }
        }
        return result.filter { $0.account != nil }
    }

    /// Parses `gh pr view --json commits`.
    nonisolated static func parseCommits(_ json: String) -> [CommitInfo] {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let commits = root["commits"] as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return commits.compactMap { commit -> CommitInfo? in
            guard let oid = commit["oid"] as? String else { return nil }
            let headline = commit["messageHeadline"] as? String ?? ""
            let body = commit["messageBody"] as? String ?? ""
            let author = (commit["authors"] as? [[String: Any]])?.first
            let name = author?["name"] as? String ?? author?["login"] as? String ?? ""
            let email = author?["email"] as? String ?? ""
            let authored = (commit["authoredDate"] as? String).flatMap(iso.date(from:)) ?? .distantPast
            let committed = (commit["committedDate"] as? String).flatMap(iso.date(from:)) ?? authored
            return CommitInfo(
                id: oid, message: body.isEmpty ? headline : "\(headline)\n\n\(body)", summary: headline,
                body: body.isEmpty ? nil : body, authorName: name, authorEmail: email, authorDate: authored,
                committerName: name, committerEmail: email, committerDate: committed, parentIDs: [], isSigned: false
            )
        }
        .reversed()
    }
}
