// Domain/Hosting/GitLabCLI.swift
// Grove
//
// Minimal wrapper around the `glab` CLI, which keeps GitLab's sign-in so Grove stores no token.

import Foundation

nonisolated enum GitLabCLI {

    static var executablePath: String? {
        ["/opt/homebrew/bin/glab", "/usr/local/bin/glab", "/usr/bin/glab"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isInstalled: Bool { executablePath != nil }

    /// Runs `glab` and returns stdout; a sign-in problem throws `notSignedIn`.
    static func run(_ arguments: [String], in directory: URL? = nil) async throws -> String {
        guard let executable = executablePath else { throw HostingError.cliMissing(.gitlab) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory { process.currentDirectoryURL = directory }
        var env = ProcessInfo.processInfo.environment
        env["NO_PROMPT"] = "1"
        env["NO_COLOR"] = "1"
        env["GLAB_NO_PROMPT"] = "1"
        process.environment = env
        let output = try await ProcessRunner.run(process)
        let stdout = String(bytes: output.stdout, encoding: .utf8) ?? ""
        guard output.status != 0 else { return stdout }
        let stderr = (String(bytes: output.stderr, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if stderr.contains("401") || stderr.contains("auth login") || stderr.localizedCaseInsensitiveContains("unauthorized") {
            throw HostingError.notSignedIn(.gitlab)
        }
        throw HostingError.unsupported(stderr.isEmpty ? "glab exited with \(output.status)" : stderr)
    }

    /// `glab api` against `path` on `host`, following pagination.
    static func api(_ path: String, host: String, method: String = "GET", fields: [String: String] = [:],
                    paginate: Bool = false) async throws -> String {
        var arguments = ["api", path, "--hostname", host]
        if method != "GET" { arguments += ["--method", method] }
        if paginate { arguments.append("--paginate") }
        for (key, value) in fields.sorted(by: { $0.key < $1.key }) { arguments += ["--raw-field", "\(key)=\(value)"] }
        return try await run(arguments)
    }

    /// Hosts `glab auth status` reports as signed in, with their user; glab writes the report to stderr.
    static func authStatus() async -> [GitHubCLI.AuthStatus] {
        guard let executable = executablePath else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["auth", "status"]
        guard let output = try? await ProcessRunner.run(process) else { return [] }
        return parseAuthStatus(String(bytes: output.stderr + output.stdout, encoding: .utf8) ?? "")
    }

    /// Lines like `gitlab.com` then `  ✓ Logged in to gitlab.com as douwe (/Users/me/.config/glab-cli/config.yml)`.
    static func parseAuthStatus(_ text: String) -> [GitHubCLI.AuthStatus] {
        text.split(separator: "\n").compactMap { raw in
            guard let range = raw.range(of: "Logged in to ") else { return nil }
            let words = raw[range.upperBound...].split(separator: " ")
            guard let host = words.first, let asIndex = words.firstIndex(of: "as"), asIndex + 1 < words.count else { return nil }
            return GitHubCLI.AuthStatus(host: String(host), account: String(words[asIndex + 1]), scopes: nil)
        }
    }

    /// GitLab addresses a project by its URL-encoded full path.
    static func projectPath(_ location: RemoteLocation) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return "projects/" + (location.fullName.addingPercentEncoding(withAllowedCharacters: unreserved) ?? location.fullName)
    }
}
