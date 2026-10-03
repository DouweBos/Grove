// Views/Settings/ServicesPreferencesTab.swift
// Grove
//
// Accounts: Grove's own sign-ins to GitHub, GitLab, Bitbucket and Azure DevOps, with tokens in the Keychain.

import GroveKit
import SwiftUI

struct ServicesPreferencesTab: View {

    @State private var viewModel = AccountsViewModel()

    var body: some View {
        Form {
            Section {
                if viewModel.accounts.isEmpty {
                    Text("No accounts yet. Add one to see pull requests and hosted repositories.")
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(viewModel.accounts) { AccountRow(account: $0, viewModel: viewModel) }
                HStack {
                    Spacer()
                    Menu("Add Account\u{2026}") {
                        ForEach(AccountProvider.allCases) { provider in
                            Button("\(provider.title)\u{2026}") { viewModel.beginAdding(provider) }
                        }
                    }
                    .fixedSize()
                }
            } header: {
                Text("Accounts")
            } footer: {
                Text("Tokens are kept in your Keychain and only sent to the service they belong to.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            if !viewModel.importable.isEmpty || viewModel.importError != nil {
                importSection
            }
            Section {
                HStack {
                    Button("Check Again") { Task { await viewModel.check() } }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .task { await viewModel.check() }
        .sheet(isPresented: Binding(get: { viewModel.form != nil }, set: { if !$0 { viewModel.cancelForm() } })) {
            AddHostingAccountSheet(viewModel: viewModel)
        }
    }

    private var importSection: some View {
        Section {
            ForEach(viewModel.importable, id: \.host) { login in
                LabeledContent {
                    HStack(spacing: Theme.Spacing.sm) {
                        if viewModel.importingHost == login.host { ProgressView().controlSize(.small) }
                        Button("Import") { Task { await viewModel.importLogin(login) } }
                            .disabled(viewModel.importingHost != nil)
                    }
                } label: {
                    Label(login.host, systemImage: login.kind.symbol)
                }
            }
            if let error = viewModel.importError {
                Text(error).font(.caption).foregroundStyle(Theme.danger)
            }
        } header: {
            Text("Import from GitHub CLI / GitLab CLI")
        } footer: {
            Text("Copies the CLI's existing sign-in into Grove. The CLI itself isn't changed.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }
}

private struct AccountRow: View {
    let account: HostingAccount
    let viewModel: AccountsViewModel

    var body: some View {
        LabeledContent {
            HStack(spacing: Theme.Spacing.sm) {
                status
                Menu {
                    Button("Re-authenticate\u{2026}") { viewModel.beginReauthenticating(account) }
                    Divider()
                    Button("Remove", role: .destructive) { viewModel.remove(account) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.title).font(.system(size: 13, weight: .medium))
                    Text(account.serviceTitle).font(.caption).foregroundStyle(Theme.textSecondary)
                }
            } icon: {
                Image(systemName: account.kind.symbol).foregroundStyle(Theme.accent)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch viewModel.statuses[account.id] {
        case .checking, nil:
            ProgressView().controlSize(.small)
        case .signedIn:
            StatusBadge(title: "Signed in", symbol: "checkmark.circle.fill", tone: .positive)
        case .failed(let message):
            StatusBadge(title: "Sign in again", symbol: "exclamationmark.triangle.fill", tone: .caution)
                .help(message)
        }
    }
}

#Preview {
    ServicesPreferencesTab().frame(width: 560, height: 520)
}
