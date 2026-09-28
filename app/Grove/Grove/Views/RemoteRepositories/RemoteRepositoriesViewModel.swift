// Views/RemoteRepositories/RemoteRepositoriesViewModel.swift
// Grove
//
// Repositories on the signed-in GitHub account and its organizations, loaded per owner on demand.

import Foundation
import Observation

@MainActor
@Observable
final class RemoteRepositoriesViewModel {

    enum OwnerState: Equatable {
        case idle
        case loading
        case loaded([RemoteRepository])
        case failed(String)
    }

    enum AccountState: Equatable {
        case unknown
        case loading
        case signedIn
        /// `gh` is missing or signed out; the message says which.
        case unavailable(String)
    }

    private(set) var account: AccountState = .unknown
    private(set) var owners: [RemoteRepositoryOwner] = []
    private(set) var states: [String: OwnerState] = [:]
    private(set) var searchText = ""
    private(set) var selectedID: String?
    /// Hosted repository key → local bookmark path, from each bookmark's remotes.
    private(set) var localClones: [String: String] = [:]

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var selected: RemoteRepository? {
        guard let selectedID else { return nil }
        for case .loaded(let repos) in states.values {
            if let match = repos.first(where: { $0.id == selectedID }) { return match }
        }
        return nil
    }

    // MARK: Loading

    /// Loads the account's owners once, then the account's own repositories.
    func loadIfNeeded() async {
        guard account == .unknown else { return }
        await reloadAccount()
    }

    func reloadAccount() async {
        account = .loading
        do {
            owners = try await GitHubCLI.repositoryOwners()
            account = .signedIn
            states = [:]
            if let first = owners.first { await load(first) }
        } catch {
            owners = []
            account = .unavailable(error.localizedDescription)
        }
    }

    func load(_ owner: RemoteRepositoryOwner) async {
        switch states[owner.login] {
        case .loading, .loaded: return
        default: break
        }
        states[owner.login] = .loading
        do {
            states[owner.login] = .loaded(try await GitHubCLI.repositories(of: owner))
        } catch {
            states[owner.login] = .failed(error.localizedDescription)
        }
    }

    func refresh(_ owner: RemoteRepositoryOwner) async {
        states[owner.login] = .idle
        await load(owner)
    }

    // MARK: Filtering & selection

    func setSearchText(_ text: String) {
        searchText = text
        // Searching covers every owner, so pull in the ones not expanded yet.
        guard isSearching else { return }
        for owner in owners where states[owner.login] == nil || states[owner.login] == .idle {
            Task { await load(owner) }
        }
    }

    func select(_ id: String?) { selectedID = id }

    func repositories(of owner: RemoteRepositoryOwner) -> [RemoteRepository] {
        guard case .loaded(let repos) = states[owner.login] else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return repos }
        return repos.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    // MARK: Local clones

    func localPath(of repository: RemoteRepository) -> String? {
        repository.matchKey.flatMap { localClones[$0] }
    }

    /// Reads each bookmark's remote URLs straight from `.git/config`; no git process per repository.
    func indexLocalClones(bookmarks: [RepositoryBookmarkData]) {
        var index: [String: String] = [:]
        for bookmark in bookmarks {
            let repoPath = WorktreeResolver.mainRepositoryPath(forWorktreeAt: bookmark.path) ?? bookmark.path
            let config = URL(fileURLWithPath: repoPath).appendingPathComponent(".git/config")
            guard let text = try? String(contentsOf: config, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix("url"), let equals = trimmed.firstIndex(of: "="),
                      let key = RemoteURLKey.make(String(trimmed[trimmed.index(after: equals)...])) else { continue }
                index[key] = index[key] ?? repoPath
            }
        }
        localClones = index
    }
}
