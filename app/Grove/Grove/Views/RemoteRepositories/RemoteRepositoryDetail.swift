// Views/RemoteRepositories/RemoteRepositoryDetail.swift
// Grove
//
// Cloud browser detail: the selected hosted repository with Clone / Open, or the account state.

import SwiftUI

struct RemoteRepositoriesContent: View {
    @Environment(WindowViewModel.self) private var windowVM
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let viewModel = windowVM.remoteRepositories
        Group {
            switch viewModel.account {
            case .unavailable(let message):
                EmptyStateView(
                    systemImage: "person.crop.circle.badge.exclamationmark",
                    title: "No Accounts",
                    subtitle: "\(message) Sign in with \u{201C}gh auth login\u{201D} or \u{201C}glab auth login\u{201D}, "
                        + "or add a Bitbucket or Azure DevOps account in Settings > Accounts.",
                    actionTitle: "Add an Account\u{2026}"
                ) { openAccounts() }
            case .unknown, .loading:
                ProgressView("Reading your accounts\u{2026}").frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedIn:
                if let repository = viewModel.selected {
                    RemoteRepositoryDetail(repository: repository)
                } else {
                    EmptyStateView(systemImage: "cloud", title: "Remote Repositories",
                                   subtitle: "Repositories on your accounts and their organizations. Select one to clone or open it.")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onChange(of: HostingAccountStore.shared.accounts) { Task { await viewModel.reloadAccount() } }
        .sheet(item: Binding(get: { viewModel.creation }, set: { if $0 == nil { viewModel.endCreating() } })) { creation in
            CreateRemoteRepositorySheet(viewModel: creation)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Remote Repository\u{2026}", systemImage: "plus.rectangle.on.folder") {
                    windowVM.showCreateRemoteRepository()
                }
                .help("Create a repository on one of your accounts")
                .disabled(viewModel.account != .signedIn)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Accounts\u{2026}", systemImage: "person.crop.circle") { openAccounts() }
                    .help("Open Settings to manage your accounts")
            }
        }
    }
}

extension RemoteRepositoriesContent {
    fileprivate func openAccounts() {
        UserDefaults.standard.set(PreferencesTab.accounts.rawValue, forKey: GrovePreferences.Key.preferencesTab)
        openSettings()
    }
}

struct RemoteRepositoryDetail: View {
    @Environment(WindowViewModel.self) private var windowVM
    let repository: RemoteRepository

    private var localPath: String? { windowVM.remoteRepositories.localPath(of: repository) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                if let description = repository.description {
                    Text(description)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                }
                facts
                urls
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(repository.name)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(repository.nameWithOwner).font(.monoCaption).foregroundStyle(Theme.textSecondary).textSelection(.enabled)
                HStack(spacing: Theme.Spacing.xs) {
                    StatusBadge(title: repository.isPrivate ? "Private" : "Public",
                                symbol: repository.isPrivate ? "lock.fill" : "globe", tone: .neutral)
                    if repository.isFork { StatusBadge(title: "Fork", symbol: "tuningfork", tone: .neutral) }
                    if repository.isArchived { StatusBadge(title: "Archived", symbol: "archivebox.fill", tone: .caution) }
                    if localPath != nil { StatusBadge(title: "On this Mac", symbol: "internaldrive.fill", tone: .positive) }
                }
            }
            Spacer(minLength: Theme.Spacing.md)
            VStack(alignment: .trailing, spacing: Theme.Spacing.sm) {
                if let localPath {
                    Button { windowVM.openLocalClone(atPath: localPath) } label: {
                        Label("Open", systemImage: "arrow.up.forward.app").padding(.horizontal, Theme.Spacing.sm)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                } else if let clone = windowVM.clones.job(matching: repository.matchKey), clone.isRunning {
                    Label("Cloning \(Int((clone.progress?.overallFraction ?? 0) * 100))%", systemImage: "arrow.down.circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Button { windowVM.showCloneDialog(url: repository.sshURL) } label: {
                        Label("Clone…", systemImage: "square.and.arrow.down").padding(.horizontal, Theme.Spacing.sm)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }
                Button("Open on \(repository.service.displayName)", systemImage: "safari") {
                    if let url = URL(string: repository.webURL) { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
            }
        }
    }

    private var facts: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            fact("Default Branch", repository.defaultBranch ?? "–")
            fact("Updated", repository.updatedAt.map { $0.formatted(.relative(presentation: .named)) } ?? "–")
            fact("Language", repository.language ?? "–")
            if let localPath { fact("Local Clone", abbreviatingHome(localPath)) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var urls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel(title: "Clone URLs")
            urlRow("SSH", repository.sshURL)
            urlRow("HTTPS", repository.httpsCloneURL)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func fact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Text(value).font(.monoCaption).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle)
        }
    }

    private func urlRow(_ label: String, _ url: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textSecondary).frame(width: 44, alignment: .leading)
            Text(url).font(.monoCaption).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
            .buttonStyle(.borderless)
            .help("Copy \(label) URL")
        }
    }
}
