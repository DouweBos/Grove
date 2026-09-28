// GitKit/GitEnvironment.swift
// Grove
//
// What Grove adds to every git process's environment: the 1Password SSH agent and signer when enabled,
// then the user's own variables, global first and the repository's on top, which hooks inherit too.

import Foundation

/// A variable the user sets for git processes, e.g. for hooks.
struct EnvironmentVariable: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name = ""
    var value = ""

    /// Empty names and names with `=` can't be exported, so they're skipped.
    var isValid: Bool { !name.isEmpty && !name.contains("=") && !name.contains(" ") }
}

nonisolated enum GitEnvironment {

    enum Key {
        static let useOnePasswordAgent = "useOnePasswordSSHAgent"
        static let useOnePasswordSigning = "useOnePasswordSSHSigning"
        static let globalVariables = "gitEnvironmentVariables"
        static func repositoryVariables(_ path: String) -> String { "gitEnvironmentVariables.\(path)" }
    }

    enum Scope: Hashable, Sendable {
        case global
        case repository(String)

        var key: String {
            switch self {
            case .global: Key.globalVariables
            case .repository(let path): Key.repositoryVariables(path)
            }
        }
    }

    static func customVariables(_ scope: Scope, defaults: UserDefaults = .standard) -> [EnvironmentVariable] {
        guard let data = defaults.data(forKey: scope.key) else { return [] }
        return (try? JSONDecoder().decode([EnvironmentVariable].self, from: data)) ?? []
    }

    static func setCustomVariables(_ variables: [EnvironmentVariable], _ scope: Scope, defaults: UserDefaults = .standard) {
        if variables.isEmpty {
            defaults.removeObject(forKey: scope.key)
        } else if let data = try? JSONEncoder().encode(variables) {
            defaults.set(data, forKey: scope.key)
        }
    }

    /// 1Password's SSH agent socket, present while the agent is enabled in 1Password.
    static var onePasswordAgentSocket: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock").path
    }

    static let onePasswordSigner = "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"

    static var isOnePasswordAgentAvailable: Bool { FileManager.default.fileExists(atPath: onePasswordAgentSocket) }
    static var isOnePasswordSignerInstalled: Bool { FileManager.default.isExecutableFile(atPath: onePasswordSigner) }

    /// Variables for a git process in `path`, layered on `base` (the inherited environment).
    static func variables(forRepositoryAt path: String?, base: [String: String],
                          defaults: UserDefaults = .standard) -> [String: String] {
        var result: [String: String] = [:]
        if defaults.bool(forKey: Key.useOnePasswordAgent) {
            result["SSH_AUTH_SOCK"] = onePasswordAgentSocket
        }
        if defaults.bool(forKey: Key.useOnePasswordSigning) {
            // Config through the environment applies to git run by Grove only, never to the user's config files.
            result.merge(configOverrides(["gpg.format": "ssh", "gpg.ssh.program": onePasswordSigner], base: base)) { $1 }
        }
        let scopes: [Scope] = [.global] + (path.map { [.repository($0)] } ?? [])
        for scope in scopes {
            for variable in customVariables(scope, defaults: defaults) where variable.isValid {
                result[variable.name] = variable.value
            }
        }
        return result
    }

    /// `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_n` / `GIT_CONFIG_VALUE_n`, appended after any the environment already has.
    static func configOverrides(_ values: [String: String], base: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        var count = Int(base["GIT_CONFIG_COUNT"] ?? "") ?? 0
        for (key, value) in values.sorted(by: { $0.key < $1.key }) {
            result["GIT_CONFIG_KEY_\(count)"] = key
            result["GIT_CONFIG_VALUE_\(count)"] = value
            count += 1
        }
        result["GIT_CONFIG_COUNT"] = String(count)
        return result
    }
}
