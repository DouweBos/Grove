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
        var pullStrategy = PullStrategy.inherit
        var remoteURLs: [String: String] = [:]
    }

    private(set) var saved = Snapshot()
    private(set) var draft = Snapshot()
    private(set) var remoteNames: [String] = []
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?
    private(set) var didSave = false

    var hasChanges: Bool { saved != draft }

    let repository: any GitRepositoryProtocol

    init(repository: any GitRepositoryProtocol) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            var snapshot = Snapshot()
            snapshot.userName = try await repository.localConfigValue("user.name") ?? ""
            snapshot.userEmail = try await repository.localConfigValue("user.email") ?? ""
            snapshot.pullStrategy = PullStrategy(configValue: try await repository.localConfigValue("pull.rebase"))
            let remotes = try await repository.remotes()
            remoteNames = remotes.map(\.name)
            snapshot.remoteURLs = Dictionary(uniqueKeysWithValues: remotes.map { ($0.name, $0.url) })
            saved = snapshot
            draft = snapshot
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Editing

    func setUserName(_ value: String) { edit { $0.userName = value } }
    func setUserEmail(_ value: String) { edit { $0.userEmail = value } }
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
