// Models/UserProfiles.swift
// Grove
//
// Named commit identities kept in Preferences; choosing one for a repository writes it to that repository's config.

import Foundation
import Observation

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

/// App-wide list of profiles, persisted in user defaults.
@MainActor
@Observable
final class UserProfileStore {

    static let shared = UserProfileStore()
    static let defaultsKey = "userProfiles"

    private(set) var profiles: [UserProfile] = []
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([UserProfile].self, from: data) {
            profiles = saved
        }
    }

    func profile(matching identity: CommitIdentity?) -> UserProfile? {
        profiles.first { $0.matches(identity) }
    }

    @discardableResult
    func add(label: String = "New Profile", userName: String = "", email: String = "") -> UserProfile {
        let profile = UserProfile(label: label, userName: userName, email: email)
        profiles.append(profile)
        save()
        return profile
    }

    func update(_ profile: UserProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index] = profile
        save()
    }

    func delete(id: UserProfile.ID) {
        profiles.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: Self.defaultsKey) }
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
