// Models/UserProfile.swift
// GroveKit
//
// A named commit identity; choosing one for a repository writes it to that repository's config.

import Foundation

struct UserProfile: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    /// What the profile is called in menus, e.g. "Work".
    var label: String
    var userName: String
    var email: String
    /// `user.signingkey`; empty leaves signing to the global config.
    var signingKey = ""

    var title: String { label.isEmpty ? email : label }

    func matches(_ identity: CommitIdentity?) -> Bool {
        guard let identity else { return false }
        return identity.name == userName && identity.email.caseInsensitiveCompare(email) == .orderedSame
    }

    /// The repository-local config a profile writes; nil unsets the key so the global value applies.
    var configValues: [(key: String, value: String?)] {
        [("user.name", userName), ("user.email", email), ("user.signingkey", signingKey.isEmpty ? nil : signingKey)]
    }
}

extension GitRepositoryProtocol {
    /// Writes the profile's identity into this repository's local config.
    func apply(_ profile: UserProfile) async throws {
        for (key, value) in profile.configValues {
            try await setLocalConfigValue(key, to: value)
        }
    }
}
