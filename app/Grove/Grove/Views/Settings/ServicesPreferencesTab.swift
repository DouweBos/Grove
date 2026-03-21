// Views/Settings/ServicesPreferencesTab.swift
// Grove
//
// Services preferences: connected Git hosting accounts (GitHub, GitLab, Bitbucket, Azure DevOps).

import SwiftUI

// MARK: - HostingService Model

/// A connected Git hosting service account.
struct HostingAccount: Identifiable, Equatable {
    var id = UUID()
    var provider: HostingProvider
    var accountName: String
    var connectionStatus: ConnectionStatus

    enum ConnectionStatus: Equatable {
        case connected
        case error(String)
        case testing
    }
}

enum HostingProvider: String, CaseIterable, Identifiable {
    case github = "GitHub"
    case gitlab = "GitLab"
    case bitbucket = "Bitbucket"
    case azureDevOps = "Azure DevOps"

    var id: String { rawValue }
    var label: String { rawValue }

    var systemImage: String {
        switch self {
        case .github: return "chevron.left.forwardslash.chevron.right"
        case .gitlab: return "cube"
        case .bitbucket: return "square.stack.3d.up"
        case .azureDevOps: return "cloud"
        }
    }

    var accentColor: Color {
        switch self {
        case .github: return .primary
        case .gitlab: return .orange
        case .bitbucket: return .blue
        case .azureDevOps: return .indigo
        }
    }
}

// MARK: - ServicesPreferencesTab

/// Preferences tab for managing connected Git hosting service accounts.
struct ServicesPreferencesTab: View {

    @State private var accounts: [HostingAccount] = [
        HostingAccount(provider: .github, accountName: "octocat", connectionStatus: .connected)
    ]
    @State private var selectedAccountID: HostingAccount.ID?
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            accountList
            Divider()
            toolbar
        }
        .sheet(isPresented: $showAddSheet) {
            AddAccountSheet(accounts: $accounts)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Account List

    @ViewBuilder
    private var accountList: some View {
        List(accounts, selection: $selectedAccountID) { account in
            AccountRow(account: account) {
                testConnection(account)
            }
        }
        .listStyle(.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                showAddSheet = true
            } label: {
                Label("Add Account", systemImage: "plus")
            }

            Button(role: .destructive) {
                removeSelectedAccount()
            } label: {
                Label("Remove Account", systemImage: "minus")
            }
            .disabled(selectedAccountID == nil)

            Spacer()

            if let id = selectedAccountID,
               let account = accounts.first(where: { $0.id == id }) {
                if case .testing = account.connectionStatus {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Test Connection") {
                        testConnection(account)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func removeSelectedAccount() {
        guard let id = selectedAccountID else { return }
        accounts.removeAll { $0.id == id }
        selectedAccountID = nil
    }

    private func testConnection(_ account: HostingAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index].connectionStatus = .testing
        Task {
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                accounts[index].connectionStatus = .connected
            }
        }
    }
}

// MARK: - AccountRow

private struct AccountRow: View {
    let account: HostingAccount
    let onTest: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.provider.systemImage)
                .font(.title2)
                .foregroundStyle(account.provider.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.accountName)
                    .fontWeight(.medium)
                Text(account.provider.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            statusBadge(for: account.connectionStatus)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(for status: HostingAccount.ConnectionStatus) -> some View {
        switch status {
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case .testing:
            ProgressView()
                .controlSize(.small)
        }
    }
}

// MARK: - AddAccountSheet

private struct AddAccountSheet: View {

    @Binding var accounts: [HostingAccount]
    @Environment(\.dismiss) private var dismiss

    @State private var selectedProvider: HostingProvider = .github
    @State private var accountName = ""
    @State private var tokenOrCredential = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Provider") {
                    Picker("Service", selection: $selectedProvider) {
                        ForEach(HostingProvider.allCases) { provider in
                            Label(provider.label, systemImage: provider.systemImage)
                                .tag(provider)
                        }
                    }
                }

                Section("Credentials") {
                    LabeledContent("Account name") {
                        TextField("username or org", text: $accountName)
                    }
                    LabeledContent("Personal access token") {
                        SecureField("ghp_…", text: $tokenOrCredential)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Section {
                    Text("OAuth sign-in flows will be supported in a future release. For now, enter a personal access token with the required scopes.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Account") {
                    let account = HostingAccount(
                        provider: selectedProvider,
                        accountName: accountName.isEmpty ? selectedProvider.label : accountName,
                        connectionStatus: .connected
                    )
                    accounts.append(account)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(accountName.isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 360)
    }
}

// MARK: - Preview

#Preview {
    ServicesPreferencesTab()
        .frame(width: 540, height: 440)
}
