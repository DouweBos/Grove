// Views/RemoteRepositories/RemoteRepositoriesViewModel.swift
// Grove
//
// Repositories on every signed-in account and its organizations, loaded per owner on demand.

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
        /// No account on any service; the message says what to set up.
        case unavailable(String)
    }

    /// One account in the sidebar with the owners it lists.
    struct Section: Identifiable {
        let catalog: any RepositoryCatalog
        var owners: [RemoteRepositoryOwner] = []
        var failure: String?
        var id: String { catalog.account.id }
        var account: CatalogAccount { catalog.account }
    }

    private(set) var account: AccountState = .unknown
    private(set) var sections: [Section] = []
    /// Keyed by `RemoteRepositoryOwner.id`.
    private(set) var states: [String: OwnerState] = [:]
    private(set) var searchText = ""
    private(set) var selectedID: String?
    /// Hosted repository key → local bookmark path, from each bookmark's remotes.
    private(set) var localClones: [String: String] = [:]

    /// The open "New Remote Repository" sheet.
    private(set) var creation: CreateRemoteRepositoryViewModel?

    /// Where the accounts come from; tests swap in fixed catalogs.
    @ObservationIgnored var catalogSource: () async -> [any RepositoryCatalog] = { await RepositoryCatalogs.all() }

    var owners: [RemoteRepositoryOwner] { sections.flatMap(\.owners) }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    var selected: RemoteRepository? {
        guard let selectedID else { return nil }
        for case .loaded(let repos) in states.values {
            if let match = repos.first(where: { $0.id == selectedID }) { return match }
        }
        return nil
    }

    // MARK: Loading

    /// Loads the accounts' owners once, then the first account's own repositories.
    func loadIfNeeded() async {
        guard account == .unknown else { return }
        await reloadAccount()
    }

    func reloadAccount() async {
        account = .loading
        states = [:]
        let catalogs = await catalogSource()
        guard !catalogs.isEmpty else {
            sections = []
            account = .unavailable("No accounts are set up.")
            return
        }
        sections = catalogs.map { Section(catalog: $0) }
        account = .signedIn
        await withTaskGroup(of: (Int, Result<[RemoteRepositoryOwner], Error>).self) { group in
            for (index, catalog) in catalogs.enumerated() {
                group.addTask {
                    do { return (index, .success(try await catalog.owners())) } catch { return (index, .failure(error)) }
                }
            }
            for await (index, result) in group {
                switch result {
                case .success(let owners): sections[index].owners = owners
                case .failure(let error): sections[index].failure = error.localizedDescription
                }
            }
        }
        if let first = sections.first(where: { !$0.owners.isEmpty })?.owners.first { await load(first) }
    }

    func load(_ owner: RemoteRepositoryOwner) async {
        switch states[owner.id] {
        case .loading, .loaded: return
        default: break
        }
        guard let catalog = sections.first(where: { $0.id == owner.accountID })?.catalog else { return }
        states[owner.id] = .loading
        do {
            states[owner.id] = .loaded(try await catalog.repositories(of: owner))
        } catch {
            states[owner.id] = .failed(error.localizedDescription)
        }
    }

    func refresh(_ owner: RemoteRepositoryOwner) async {
        states[owner.id] = .idle
        await load(owner)
    }

    // MARK: Filtering & selection

    func setSearchText(_ text: String) {
        searchText = text
        // Searching covers every owner, so pull in the ones not expanded yet.
        guard isSearching else { return }
        for owner in owners where states[owner.id] == nil || states[owner.id] == .idle {
            Task { await load(owner) }
        }
    }

    func select(_ id: String?) { selectedID = id }

    func repositories(of owner: RemoteRepositoryOwner) -> [RemoteRepository] {
        guard case .loaded(let repos) = states[owner.id] else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return repos }
        return repos.filter {
            $0.name.localizedCaseInsensitiveContains(query) || ($0.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    // MARK: Creating

    /// Opens the sheet on `owner` (the first account's own when nil); `targets` are local repositories to add it to as a remote.
    func beginCreating(owner: RemoteRepositoryOwner? = nil, targets: [CreateRemoteRepositoryViewModel.Target] = [],
                       preferredTarget: String? = nil,
                       addRemote: ((String, String, String) async throws -> Void)? = nil) {
        let creation = CreateRemoteRepositoryViewModel(sections: { [weak self] in self?.sections ?? [] }, owner: owner, targets: targets,
                                                       preferredTarget: preferredTarget)
        creation.addRemote = addRemote
        creation.onCreated = { [weak self] repository, owner in self?.didCreate(repository, under: owner) }
        self.creation = creation
    }

    func endCreating() { creation = nil }

    /// Lists the new repository at the top of its owner and selects it, without a reload the service may not reflect yet.
    private func didCreate(_ repository: RemoteRepository, under owner: RemoteRepositoryOwner) {
        if case .loaded(let repos) = states[owner.id] {
            states[owner.id] = .loaded([repository] + repos.filter { $0.id != repository.id })
        } else {
            states[owner.id] = .loaded([repository])
        }
        selectedID = repository.id
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
