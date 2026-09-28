// Views/PullRequests/PRUnavailableView.swift
// Grove

import SwiftUI

/// Why the list couldn't load, so the view can offer the right fix.
enum PRLoadFailure: Equatable {
    case notSignedIn(HostingServiceKind)
    /// A REST service with no account for this host in Preferences > Accounts.
    case noAccount(HostingServiceKind, host: String)
    case noHostedRemote
    case other(String)

    init(_ error: Error) {
        if let hosting = error as? HostingError {
            switch hosting {
            case .notSignedIn(let kind): self = .notSignedIn(kind)
            case .noAccount(let kind, let host): self = .noAccount(kind, host: host)
            case .noHostedRemote: self = .noHostedRemote
            case .unsupported, .http: self = .other(hosting.localizedDescription)
            }
            return
        }
        self = .other(error.localizedDescription)
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
        UserDefaults.standard.set(PreferencesTab.accounts.rawValue, forKey: PreferencesTab.storageKey)
        openSettings()
    }

    private var symbol: String {
        if case .noAccount = failure { return "person.crop.circle.badge.plus" }
        return "arrow.triangle.pull"
    }

    private var title: String {
        switch failure {
        case .notSignedIn(let kind): "Sign In to \(kind.displayName) Again"
        case .noAccount(let kind, _): "Add a \(kind.displayName) Account"
        case .noHostedRemote: "No Hosted Remote"
        case .other: "Couldn't Load Pull Requests"
        }
    }

    private var subtitle: String {
        switch failure {
        case .notSignedIn(let kind): "\(kind.displayName) refused the saved token; it may have expired or been revoked."
        case .noAccount(let kind, let host):
            "This repository lives on \(host). Add a \(kind.displayName) account to see its \(kind.pullRequestNoun.lowercased())s."
        case .noHostedRemote: "None of this repository's remotes point at GitHub, GitLab, Bitbucket or Azure DevOps."
        case .other: "The service returned an error."
        }
    }

    private var bannerMessage: String {
        switch failure {
        case .notSignedIn: "Re-authenticate the account in Settings > Accounts, then try again."
        case .noHostedRemote: "Add a remote in Repository Settings to see its pull requests."
        case .noAccount: ""
        case .other(let message): message
        }
    }

    private var actionTitle: String? {
        if case .notSignedIn = failure { return "Open Accounts" }
        return nil
    }

    private var action: (() -> Void)? {
        if case .notSignedIn = failure { return { openAccounts() } }
        return nil
    }
}

#Preview {
    PRUnavailableView(failure: .noAccount(.bitbucket, host: "bitbucket.org"))
        .environment(PullRequestsViewModel(repository: MockGitRepository()))
        .frame(width: 600, height: 400)
        .background(Theme.surface)
}
