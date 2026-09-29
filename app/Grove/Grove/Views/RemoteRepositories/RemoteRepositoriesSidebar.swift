// Views/RemoteRepositories/RemoteRepositoriesSidebar.swift
// Grove
//
// Cloud browser sidebar: each signed-in account with its organizations, each listing its repositories.

import SwiftUI

struct RemoteRepositoriesSidebar: View {
    @Environment(WindowViewModel.self) private var windowVM
    private var viewModel: RemoteRepositoriesViewModel { windowVM.remoteRepositories }

    var body: some View {
        List(selection: Binding(get: { viewModel.selectedID }, set: { viewModel.select($0) })) {
            switch viewModel.account {
            case .unknown, .loading:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity).selectionDisabled()
            case .unavailable:
                EmptyView()
            case .signedIn:
                ForEach(viewModel.sections) { section in
                    Section {
                        if let failure = section.failure {
                            Text(failure).font(.system(size: 12)).foregroundStyle(Theme.danger).lineLimit(3).selectionDisabled()
                        }
                        ForEach(section.owners) { RemoteOwnerSection(owner: $0) }
                    } header: {
                        SectionLabel(title: "\(section.account.kind.displayName) \u{00B7} \(section.account.title)")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(
            text: Binding(get: { viewModel.searchText }, set: { viewModel.setSearchText($0) }),
            placement: .sidebar,
            prompt: "Filter Remote Repositories"
        )
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let repo = repository(withID: id) {
                RemoteRepositoryActions(repository: repo)
            }
        } primaryAction: { ids in
            guard let id = ids.first, let repo = repository(withID: id) else { return }
            if let path = viewModel.localPath(of: repo) {
                windowVM.openLocalClone(atPath: path)
            } else {
                windowVM.showCloneDialog(url: repo.defaultCloneURL)
            }
        }
    }

    private func repository(withID id: String) -> RemoteRepository? {
        viewModel.owners.lazy.flatMap { viewModel.repositories(of: $0) }.first { $0.id == id }
    }
}

// MARK: - RemoteOwnerSection

/// One account or organization; its repositories load the first time it's expanded.
private struct RemoteOwnerSection: View {
    @Environment(WindowViewModel.self) private var windowVM
    let owner: RemoteRepositoryOwner
    @State private var isExpanded: Bool

    init(owner: RemoteRepositoryOwner) {
        self.owner = owner
        _isExpanded = State(initialValue: owner.isAccount)
    }

    private var viewModel: RemoteRepositoriesViewModel { windowVM.remoteRepositories }

    var body: some View {
        let repositories = viewModel.repositories(of: owner)
        DisclosureGroup(isExpanded: Binding(
            get: { isExpanded || (viewModel.isSearching && !repositories.isEmpty) },
            set: { isExpanded = $0; if $0 { Task { await viewModel.load(owner) } } }
        )) {
            switch viewModel.states[owner.id] ?? .idle {
            case .idle, .loading:
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Loading…").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                }
                .selectionDisabled()
            case .failed(let message):
                Text(message).font(.system(size: 12)).foregroundStyle(Theme.danger).lineLimit(3).selectionDisabled()
            case .loaded:
                ForEach(repositories) { repo in
                    RemoteRepositoryRow(repository: repo, isCloned: viewModel.localPath(of: repo) != nil,
                                        clone: windowVM.clones.job(matching: repo.matchKey))
                        .tag(repo.id)
                }
            }
        } label: {
            SidebarRow(title: owner.title, symbol: owner.isAccount ? "person.crop.circle" : "building.2", tint: Theme.accent,
                       isEmphasized: true) {
                if case .loaded(let all) = viewModel.states[owner.id] {
                    Text("\(all.count)").font(.system(size: 11, weight: .semibold, design: .rounded))
                }
            }
            .contextMenu {
                Button("Reload", systemImage: "arrow.clockwise") { Task { await viewModel.refresh(owner) } }
                Button("New Repository in \u{201C}\(owner.title)\u{201D}\u{2026}", systemImage: "plus.rectangle.on.folder") {
                    windowVM.showCreateRemoteRepository(owner: owner)
                }
            }
        }
    }
}

// MARK: - RemoteRepositoryRow

struct RemoteRepositoryRow: View {
    let repository: RemoteRepository
    let isCloned: Bool
    /// A clone of this repository running or failed in the background.
    var clone: CloneQueue.Job?

    var body: some View {
        SidebarRow(
            title: repository.name,
            symbol: isCloned ? "internaldrive" : (repository.isFork ? "tuningfork" : "cloud"),
            tint: isCloned ? Theme.success : Theme.textSecondary
        ) {
            HStack(spacing: Theme.Spacing.xs) {
                if let clone {
                    if clone.isRunning {
                        ProgressView(value: clone.progress?.overallFraction ?? 0).progressViewStyle(.circular).controlSize(.mini)
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger).accessibilityLabel("Clone failed")
                    }
                }
                if repository.isArchived { Image(systemName: "archivebox").accessibilityLabel("Archived") }
                if repository.isPrivate { Image(systemName: "lock.fill").accessibilityLabel("Private") }
            }
            .font(.system(size: 10))
        }
        .opacity(repository.isArchived ? 0.6 : 1)
        .help(isCloned ? "\(repository.nameWithOwner) — cloned on this Mac" : repository.nameWithOwner)
    }
}

// MARK: - RemoteRepositoryActions

struct RemoteRepositoryActions: View {
    @Environment(WindowViewModel.self) private var windowVM
    let repository: RemoteRepository

    var body: some View {
        if let path = windowVM.remoteRepositories.localPath(of: repository) {
            Button("Open Local Clone", systemImage: "arrow.up.forward.app") { windowVM.openLocalClone(atPath: path) }
        }
        Button("Clone…", systemImage: "square.and.arrow.down") { windowVM.showCloneDialog(url: repository.defaultCloneURL) }
            .disabled(windowVM.clones.job(matching: repository.matchKey)?.isRunning == true)
        Button("Open on \(repository.service.displayName)", systemImage: "safari") {
            if let url = URL(string: repository.webURL) { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button("Copy SSH URL", systemImage: "doc.on.doc") { copy(repository.sshURL) }
        Button("Copy HTTPS URL", systemImage: "doc.on.doc") { copy(repository.httpsCloneURL) }
    }

    private func copy(_ text: String) {
        GroveClipboard.copy(text)
    }
}
