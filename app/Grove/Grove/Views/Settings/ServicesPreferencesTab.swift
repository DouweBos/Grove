// Views/Settings/ServicesPreferencesTab.swift
// Grove
//
// Accounts: Grove talks to GitHub through the `gh` CLI, so this shows its real sign-in state.

import SwiftUI

struct ServicesPreferencesTab: View {

    private enum Status: Equatable {
        case checking
        case missing
        case signedOut
        case signedIn([GitHubCLI.AuthStatus])
        case failed(String)
    }

    @State private var status: Status = .checking

    var body: some View {
        Form {
            Section {
                LabeledContent("GitHub CLI") {
                    Text(GitHubCLI.executablePath ?? "Not installed")
                        .font(.monoCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
                statusRows
            } header: {
                Text("GitHub")
            } footer: {
                Text("Pull requests are loaded with gh using its own sign-in. Grove never stores tokens.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Section {
                HStack {
                    Button("Check Again") { Task { await check() } }
                        .disabled(status == .checking)
                    Spacer()
                    switch status {
                    case .missing:
                        Button("Get GitHub CLI") { NSWorkspace.shared.open(URL(string: "https://cli.github.com")!) }
                    case .signedOut, .failed:
                        Button("Copy \u{201C}gh auth login\u{201D}") { GroveClipboard.copy("gh auth login") }
                        Button("Open Terminal") { try? ExternalToolLauncher.openInTerminal(FileManager.default.homeDirectoryForCurrentUser) }
                    case .checking, .signedIn:
                        EmptyView()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { await check() }
    }

    @ViewBuilder
    private var statusRows: some View {
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

    private func check() async {
        guard GitHubCLI.isInstalled else { status = .missing; return }
        status = .checking
        do {
            let accounts = try await GitHubCLI.authStatus()
            status = accounts.isEmpty ? .signedOut : .signedIn(accounts)
        } catch GitHubCLI.Failure.notAuthenticated {
            status = .signedOut
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

#Preview {
    ServicesPreferencesTab().frame(width: 520, height: 400)
}
