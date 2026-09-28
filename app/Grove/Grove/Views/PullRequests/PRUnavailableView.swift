// Views/PullRequests/PRUnavailableView.swift
// Grove

import SwiftUI

/// Why the list couldn't load, so the view can offer the right fix.
enum PRLoadFailure: Equatable {
    case cliMissing(HostingServiceKind)
    case notSignedIn(HostingServiceKind)
    /// A REST service with no account for this host in Preferences > Accounts.
    case noAccount(HostingServiceKind, host: String)
    case noHostedRemote
    case other(String)

    init(_ error: Error) {
        if let hosting = error as? HostingError {
            switch hosting {
            case .cliMissing(let kind): self = .cliMissing(kind)
            case .notSignedIn(let kind): self = .notSignedIn(kind)
            case .noAccount(let kind, let host): self = .noAccount(kind, host: host)
            case .noHostedRemote: self = .noHostedRemote
            case .unsupported, .http: self = .other(hosting.localizedDescription)
            }
            return
        }
        let text = error.localizedDescription
        if case GitHubCLI.Failure.notInstalled = error { self = .cliMissing(.github); return }
        if case GitHubCLI.Failure.notAuthenticated = error { self = .notSignedIn(.github); return }
        if text.contains("gh auth login") || text.contains("not logged") { self = .notSignedIn(.github); return }
        if text.contains("known GitHub host") || text.contains("no git remotes") { self = .noHostedRemote; return }
        self = .other(text)
    }
}

struct PRUnavailableView: View {
    @Environment(PullRequestsViewModel.self) private var viewModel
    @Environment(\.openSettings) private var openSettings
    let failure: PRLoadFailure

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 56, height: 56)
                .background(Theme.subtleFill, in: Circle())
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, Theme.Spacing.sm)
            if case .noAccount = failure {
                Button("Add an Account\u{2026}") { openAccounts() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            } else {
                Banner(symbol: "exclamationmark.triangle", message: bannerMessage, actionTitle: actionTitle, action: action)
                    .frame(maxWidth: 560)
            }
            Button("Try Again") { Task { await viewModel.refresh() } }
                .disabled(viewModel.isLoading)
        }
        .padding(Theme.Spacing.xl)
    }

    private func openAccounts() {
        UserDefaults.standard.set(PreferencesTab.accounts.rawValue, forKey: GrovePreferences.Key.preferencesTab)
        openSettings()
    }

    private var symbol: String {
        if case .noAccount = failure { return "person.crop.circle.badge.plus" }
        return "arrow.triangle.pull"
    }

    private var title: String {
        switch failure {
        case .cliMissing(let kind): "\(cliName(kind)) Needed"
        case .notSignedIn(let kind): "Sign In to \(kind.displayName)"
        case .noAccount(let kind, _): "Add a \(kind.displayName) Account"
        case .noHostedRemote: "No Hosted Remote"
        case .other: "Couldn't Load Pull Requests"
        }
    }

    private var subtitle: String {
        switch failure {
        case .cliMissing(let kind): "Grove reads \(kind.displayName) \(kind.pullRequestNoun.lowercased())s through \(cliCommand(kind))."
        case .notSignedIn(let kind) where kind == .github || kind == .gitlab:
            "\(cliCommand(kind)) is installed but not signed in."
        case .notSignedIn(let kind): "\(kind.displayName) refused the saved token. Replace it in Settings > Accounts."
        case .noAccount(let kind, let host):
            "This repository lives on \(host). Add a \(kind.displayName) account with an \(tokenName(kind)) to see its pull requests."
        case .noHostedRemote: "None of this repository's remotes point at GitHub, GitLab, Bitbucket or Azure DevOps."
        case .other: "The service returned an error."
        }
    }

    private var bannerMessage: String {
        switch failure {
        case .cliMissing(let kind): "Install it with Homebrew: brew install \(cliCommand(kind))"
        case .notSignedIn(let kind) where kind == .github || kind == .gitlab:
            "Run \u{201C}\(cliCommand(kind)) auth login\u{201D} in Terminal, then try again."
        case .notSignedIn: "Open Settings > Accounts, remove the account and add it again with a new token."
        case .noHostedRemote: "Add a remote in Repository Settings to see its pull requests."
        case .noAccount: ""
        case .other(let message): message
        }
    }

    private var actionTitle: String? {
        switch failure {
        case .cliMissing(let kind): kind == .gitlab ? "Open gitlab.com/gitlab-org/cli" : "Open cli.github.com"
        case .notSignedIn(let kind) where kind == .github || kind == .gitlab: "Open Terminal"
        case .notSignedIn: "Open Accounts"
        case .noAccount, .noHostedRemote, .other: nil
        }
    }

    private var action: (() -> Void)? {
        switch failure {
        case .cliMissing(let kind):
            let page = kind == .gitlab ? "https://gitlab.com/gitlab-org/cli" : "https://cli.github.com"
            return { if let url = URL(string: page) { NSWorkspace.shared.open(url) } }
        case .notSignedIn(let kind) where kind == .github || kind == .gitlab:
            return { try? ExternalToolLauncher.openInTerminal(viewModel.repository.path) }
        case .notSignedIn: return { openAccounts() }
        case .noAccount, .noHostedRemote, .other: return nil
        }
    }

    private func cliCommand(_ kind: HostingServiceKind) -> String { kind == .gitlab ? "glab" : "gh" }
    private func cliName(_ kind: HostingServiceKind) -> String { kind == .gitlab ? "GitLab CLI" : "GitHub CLI" }
    private func tokenName(_ kind: HostingServiceKind) -> String { kind == .bitbucket ? "app password" : "access token" }
}

#Preview {
    PRUnavailableView(failure: .noAccount(.bitbucket, host: "bitbucket.org"))
        .environment(PullRequestsViewModel(repository: MockGitRepository()))
        .frame(width: 600, height: 400)
        .background(Theme.surface)
}
