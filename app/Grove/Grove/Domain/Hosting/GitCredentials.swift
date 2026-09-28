// Domain/Hosting/GitCredentials.swift
// Grove
//
// Grove's accounts as a fallback for git's HTTPS username/password prompts, for Grove's own git processes only.

import Foundation

/// Answers git's prompts through `GIT_ASKPASS`. git asks its own credential helpers first, so this only fills in
/// when nothing else knows the host; the user's git config is never touched.
nonisolated enum GitCredentials {

    struct Entry: Equatable, Sendable {
        let host: String
        let username: String
        let secret: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var entries: [Entry] = []

    /// Replaces the credentials handed to git; called whenever accounts change.
    static func update(_ accounts: [(HostingAccount, String)]) {
        let new = accounts.map { account, secret in Entry(host: account.host, username: username(for: account), secret: secret) }
        lock.withLock { entries = new }
    }

    /// The user name git should send with the token: GitHub and Azure DevOps ignore it, GitLab wants `oauth2`.
    static func username(for account: HostingAccount) -> String {
        switch account.kind {
        case .github: account.username.isEmpty ? "x-access-token" : account.username
        case .gitlab: "oauth2"
        case .bitbucket: account.username
        case .azureDevOps: account.username.isEmpty ? "grove" : account.username
        }
    }

    /// Variables merged into every git process; empty without accounts, so git behaves as before.
    static func environment() -> [String: String] {
        let current = lock.withLock { entries }
        guard !current.isEmpty, let script = askpassScript() else { return [:] }
        var env = ["GIT_ASKPASS": script, "GROVE_CREDENTIAL_COUNT": String(current.count)]
        for (index, entry) in current.enumerated() {
            env["GROVE_CREDENTIAL_\(index)_HOST"] = entry.host
            env["GROVE_CREDENTIAL_\(index)_USER"] = entry.username
            env["GROVE_CREDENTIAL_\(index)_SECRET"] = entry.secret
        }
        return env
    }

    /// Prompts look like `Username for 'https://github.com': ` and `Password for 'https://me@github.com': `.
    static let script = """
    #!/bin/sh
    # Grove: answers git's HTTPS prompts for hosts Grove has an account for.
    prompt="$1"
    i=0
    while [ "$i" -lt "${GROVE_CREDENTIAL_COUNT:-0}" ]; do
      host=$(printenv "GROVE_CREDENTIAL_${i}_HOST")
      case "$prompt" in
        *"://$host'"*|*"@$host'"*)
          case "$prompt" in
            Username*) printenv "GROVE_CREDENTIAL_${i}_USER" ;;
            *) printenv "GROVE_CREDENTIAL_${i}_SECRET" ;;
          esac
          exit 0 ;;
      esac
      i=$((i + 1))
    done
    exit 1

    """

    /// Written once per launch to the temporary directory, readable and runnable by the user only.
    private static func askpassScript() -> String? {
        lock.withLock {
            if let written = writtenScript { return written }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("grove-git-askpass-\(getpid()).sh")
            do {
                try Data(script.utf8).write(to: url, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
                writtenScript = url.path
                return url.path
            } catch {
                return nil
            }
        }
    }

    nonisolated(unsafe) private static var writtenScript: String?
}
