// Models/UserProfiles.swift
// Grove
//
// The named commit identities kept in Preferences.

import Foundation
import GroveKit
import Observation

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
