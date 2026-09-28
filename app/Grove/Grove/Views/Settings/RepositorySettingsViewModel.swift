// Views/Settings/RepositorySettingsViewModel.swift
// Grove

import Foundation
import Observation

/// Edits the repository's local `.git/config`: identity, pull strategy and remote URLs.
@MainActor
@Observable
final class RepositorySettingsViewModel {

    enum PullStrategy: String, CaseIterable, Identifiable {
        case inherit, merge, rebase
        var id: String { rawValue }
        var title: String {
            switch self {
            case .inherit: "Use Global Setting"
            case .merge: "Merge"
            case .rebase: "Rebase"
            }
        }
        /// Local `pull.rebase` value; nil unsets it.
        var configValue: String? {
            switch self {
            case .inherit: nil
            case .merge: "false"
            case .rebase: "true"
            }
        }
        init(configValue: String?) {
            switch configValue?.lowercased() {
            case "true", "merges", "interactive", "i", "m": self = .rebase
            case "false": self = .merge
            default: self = .inherit
            }
        }
    }

    struct Snapshot: Equatable {
        var userName = ""
        var userEmail = ""
        var userSigningKey = ""
        var pullStrategy = PullStrategy.inherit
        var remoteURLs: [String: String] = [:]
    }

    private(set) var saved = Snapshot()
    private(set) var draft = Snapshot()
    private(set) var remoteNames: [String] = []
    private(set) var isLoading = false
    /// False until the first read, so the form is only disabled before any values exist.
    private(set) var hasLoaded = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var didSave = false

    var hasChanges: Bool { saved != draft }

    let repository: any GitRepositoryProtocol

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    /// Re-reads config while the last values stay on screen; fields the user is editing keep their draft.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let repository = repository
            async let name = repository.localConfigValue("user.name")
            async let email = repository.localConfigValue("user.email")
            async let signingKey = repository.localConfigValue("user.signingkey")
            async let rebase = repository.localConfigValue("pull.rebase")
            async let remoteList = repository.remotes()
            var snapshot = Snapshot()
            snapshot.userName = try await name ?? ""
            snapshot.userEmail = try await email ?? ""
            snapshot.userSigningKey = try await signingKey ?? ""
            snapshot.pullStrategy = PullStrategy(configValue: try await rebase)
            let remotes = try await remoteList
            snapshot.remoteURLs = Dictionary(remotes.map { ($0.name, $0.url) }) { first, _ in first }
            remoteNames = remotes.map(\.name)
            draft = Self.rebase(draft: draft, from: saved, onto: snapshot)
            saved = snapshot
            hasLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Applies `new` to every field of `draft` the user hasn't changed from `old`.
    static func rebase(draft: Snapshot, from old: Snapshot, onto new: Snapshot) -> Snapshot {
        var result = new
        if draft.userName != old.userName { result.userName = draft.userName }
        if draft.userEmail != old.userEmail { result.userEmail = draft.userEmail }
        if draft.userSigningKey != old.userSigningKey { result.userSigningKey = draft.userSigningKey }
        if draft.pullStrategy != old.pullStrategy { result.pullStrategy = draft.pullStrategy }
        for (remote, url) in draft.remoteURLs where new.remoteURLs[remote] != nil && url != old.remoteURLs[remote] {
            result.remoteURLs[remote] = url
        }
        return result
    }

    // MARK: - Editing

    func setUserName(_ value: String) { edit { $0.userName = value } }
    func setUserEmail(_ value: String) { edit { $0.userEmail = value } }
    func setUserSigningKey(_ value: String) { edit { $0.userSigningKey = value } }

    /// Fills the identity fields from a profile; Save writes them.
    func applyProfile(_ profile: UserProfile) {
        edit {
            $0.userName = profile.userName
            $0.userEmail = profile.email
            $0.userSigningKey = profile.signingKey
        }
    }

    /// The profile the identity fields currently match, if any.
    func matchingProfile(in profiles: [UserProfile]) -> UserProfile? {
        profiles.first { $0.matches(CommitIdentity(name: draft.userName, email: draft.userEmail)) && $0.signingKey == draft.userSigningKey }
    }
    func setPullStrategy(_ value: PullStrategy) { edit { $0.pullStrategy = value } }
    func setRemoteURL(_ url: String, for remote: String) { edit { $0.remoteURLs[remote] = url } }

    func revert() {
        draft = saved
    }

    private func edit(_ change: (inout Snapshot) -> Void) {
        change(&draft)
        didSave = false
    }

    // MARK: - Saving

    func save() async {
        isSaving = true
        defer { isSaving = false }
        let target = draft
        do {
            if target.userName != saved.userName {
                try await repository.setLocalConfigValue("user.name", to: trimmed(target.userName))
            }
            if target.userEmail != saved.userEmail {
                try await repository.setLocalConfigValue("user.email", to: trimmed(target.userEmail))
            }
            if target.userSigningKey != saved.userSigningKey {
                try await repository.setLocalConfigValue("user.signingkey", to: trimmed(target.userSigningKey))
            }
            if target.pullStrategy != saved.pullStrategy {
                try await repository.setLocalConfigValue("pull.rebase", to: target.pullStrategy.configValue)
            }
            for name in remoteNames {
                let url = trimmed(target.remoteURLs[name] ?? "")
                if url != saved.remoteURLs[name], !url.isEmpty {
                    try await repository.setRemoteURL(url, forRemote: name)
                }
            }
            await load()
            didSave = errorMessage == nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
