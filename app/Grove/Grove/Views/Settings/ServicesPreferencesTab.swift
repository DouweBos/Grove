// Views/Settings/ServicesPreferencesTab.swift
// Grove
//
// Accounts: GitHub and GitLab through their CLIs' own sign-in, Bitbucket and Azure DevOps with tokens in the Keychain.

import SwiftUI

struct ServicesPreferencesTab: View {

    @State private var viewModel = AccountsViewModel()

    var body: some View {
        Form {
            cliSection(.github, path: GitHubCLI.executablePath, status: viewModel.github,
                       footer: "Pull requests are loaded with gh using its own sign-in. Grove never stores GitHub tokens.")
            cliSection(.gitlab, path: GitLabCLI.executablePath, status: viewModel.gitlab,
                       footer: "Merge requests are loaded with glab using its own sign-in, including self-hosted GitLab.")
            Section {
                if viewModel.accounts.isEmpty {
                    Text("No accounts yet.").foregroundStyle(Theme.textSecondary)
                }
                ForEach(viewModel.accounts) { account in
                    LabeledContent {
                        Button("Remove", role: .destructive) { viewModel.remove(account) }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.title).font(.system(size: 13, weight: .medium))
                                Text(account.kind.displayName).font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        } icon: {
                            Image(systemName: account.kind.symbol).foregroundStyle(Theme.accent)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Menu("Add Account\u{2026}") {
                        Button("Bitbucket\u{2026}") { viewModel.beginAdding(.bitbucket) }
                        Button("Azure DevOps\u{2026}") { viewModel.beginAdding(.azureDevOps) }
                    }
                    .fixedSize()
                }
            } header: {
                Text("Bitbucket and Azure DevOps")
            } footer: {
                Text("Tokens are kept in your Keychain and only sent to the service they belong to.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Section {
                HStack {
                    Button("Check Again") { Task { await viewModel.check() } }
                        .disabled(viewModel.github == .checking || viewModel.gitlab == .checking)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .task { await viewModel.check() }
        .sheet(item: Binding(get: { viewModel.addition.map(FormID.init) }, set: { if $0 == nil { viewModel.cancelAdding() } })) { _ in
            AddHostingAccountSheet(viewModel: viewModel)
        }
    }

    private struct FormID: Identifiable {
        let form: AddAccountForm
        // Constant, so switching the service in the sheet keeps it up.
        var id: String { "add-account" }
    }

    @ViewBuilder
    private func cliSection(_ kind: HostingServiceKind, path: String?, status: AccountsViewModel.CLIStatus, footer: String) -> some View {
        let command = kind == .gitlab ? "glab" : "gh"
        Section {
            LabeledContent("\(kind.displayName) CLI") {
                Text(path ?? "Not installed").font(.monoCaption).foregroundStyle(Theme.textSecondary)
            }
            statusRows(status)
            switch status {
            case .missing:
                HStack {
                    Spacer()
                    Button("Get \(kind.displayName) CLI") {
                        let page = kind == .gitlab ? "https://gitlab.com/gitlab-org/cli" : "https://cli.github.com"
                        if let url = URL(string: page) { NSWorkspace.shared.open(url) }
                    }
                }
            case .signedOut, .failed:
                HStack {
                    Spacer()
                    Button("Copy \u{201C}\(command) auth login\u{201D}") { GroveClipboard.copy("\(command) auth login") }
                    Button("Open Terminal") { try? ExternalToolLauncher.openInTerminal(FileManager.default.homeDirectoryForCurrentUser) }
                }
            case .checking, .signedIn:
                EmptyView()
            }
        } header: {
            Text(kind.displayName)
        } footer: {
            Text(footer).font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private func statusRows(_ status: AccountsViewModel.CLIStatus) -> some View {
        switch status {
        case .checking:
            LabeledContent("Status") { ProgressView().controlSize(.small) }
        case .missing:
            LabeledContent("Status") { StatusBadge(title: "Not installed", symbol: "xmark.octagon.fill", tone: .negative) }
        case .signedOut:
            LabeledContent("Status") { StatusBadge(title: "Signed out", symbol: "exclamationmark.triangle.fill", tone: .caution) }
        case .failed(let message):
            LabeledContent("Status") { StatusBadge(title: "Error", symbol: "exclamationmark.triangle.fill", tone: .caution) }
            Text(message).font(.caption).foregroundStyle(Theme.textSecondary)
        case .signedIn(let accounts):
            ForEach(accounts, id: \.host) { account in
                LabeledContent(account.host) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(account.account ?? "").font(.system(size: 13, weight: .medium))
                        StatusBadge(title: "Signed in", symbol: "checkmark.circle.fill", tone: .positive)
                    }
                }
                if let scopes = account.scopes {
                    LabeledContent("Token scopes") {
                        Text(scopes).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}

#Preview {
    ServicesPreferencesTab().frame(width: 560, height: 620)
}
