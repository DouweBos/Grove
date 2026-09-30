// Views/Hosting/HostUnavailableView.swift
// Grove
//
// The "can't reach the host" state shared by every tab that reads from the hosting service.

import SwiftUI

/// Why a host-backed list couldn't load, so the view can offer the right fix.
enum HostLoadFailure: Equatable {
    case notSignedIn(HostingServiceKind)
    /// A REST service with no account for this host in Preferences > Accounts.
    case noAccount(HostingServiceKind, host: String)
    case noHostedRemote
    /// Grove knows the service but doesn't offer this feature on it yet.
    case unsupportedHost(HostingServiceKind)
    /// The token works but isn't allowed to do this (HTTP 403).
    case forbidden(String)
    case other(String)

    init(_ error: Error) {
        if let hosting = error as? HostingError {
            switch hosting {
            case .notSignedIn(let kind): self = .notSignedIn(kind)
            case .noAccount(let kind, let host): self = .noAccount(kind, host: host)
            case .noHostedRemote: self = .noHostedRemote
            case .ciUnsupported(let kind): self = .unsupportedHost(kind)
            case .http(status: 403, let message): self = .forbidden(message)
            case .unsupported, .http: self = .other(hosting.localizedDescription)
            }
            return
        }
        self = .other(error.localizedDescription)
    }
}

/// What a host-backed tab shows, for the wording of its unavailable state.
enum HostFeature {
    case pullRequests, ci

    var title: String {
        switch self {
        case .pullRequests: "Pull Requests"
        case .ci: "Workflow Runs"
        }
    }

    var symbol: String {
        switch self {
        case .pullRequests: "arrow.triangle.pull"
        case .ci: "play.circle"
        }
    }

    /// "pull requests", or GitLab's "merge requests".
    func noun(on kind: HostingServiceKind?) -> String {
        switch self {
        case .pullRequests: (kind?.pullRequestNoun ?? "Pull Request").lowercased() + "s"
        case .ci: "workflow runs"
        }
    }

    /// What the token needs, shown when the host answers 403.
    var permissionHint: String {
        switch self {
        case .pullRequests: "The token needs access to this repository and its pull requests."
        case .ci: "Fine-grained tokens need Actions (read and write) and Contents (read) access to this repository; "
            + "classic tokens need the repo scope."
        }
    }
}

struct HostUnavailableView: View {
    @Environment(\.openSettings) private var openSettings
    let failure: HostLoadFailure
    let feature: HostFeature
    var isLoading = false
    let onRetry: () -> Void

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
            } else if let bannerMessage {
                Banner(symbol: "exclamationmark.triangle", message: bannerMessage, actionTitle: opensAccounts ? "Open Accounts" : nil,
                       action: opensAccounts ? { openAccounts() } : nil)
                    .frame(maxWidth: 560)
            }
            if canRetry {
                Button("Try Again", action: onRetry)
                    .disabled(isLoading)
            }
        }
        .padding(Theme.Spacing.xl)
    }

    private func openAccounts() {
        UserDefaults.standard.set(PreferencesTab.accounts.rawValue, forKey: PreferencesTab.storageKey)
        openSettings()
    }

    private var symbol: String {
        if case .noAccount = failure { return "person.crop.circle.badge.plus" }
        return feature.symbol
    }

    private var title: String {
        switch failure {
        case .notSignedIn(let kind): "Sign In to \(kind.displayName) Again"
        case .noAccount(let kind, _): "Add a \(kind.displayName) Account"
        case .noHostedRemote: "No Hosted Remote"
        case .unsupportedHost(let kind): "\(kind.displayName) Isn't Supported Yet"
        case .forbidden: "No Access to \(feature.title)"
        case .other: "Couldn't Load \(feature.title)"
        }
    }

    private var subtitle: String {
        switch failure {
        case .notSignedIn(let kind): "\(kind.displayName) refused the saved token; it may have expired or been revoked."
        case .noAccount(let kind, let host):
            "This repository lives on \(host). Add a \(kind.displayName) account to see its \(feature.noun(on: kind))."
        case .noHostedRemote: "None of this repository's remotes point at GitHub, GitLab, Bitbucket or Azure DevOps."
        case .unsupportedHost(let kind): "Grove can't show \(feature.noun(on: kind)) from \(kind.displayName) yet."
        case .forbidden: feature.permissionHint
        case .other: "The service returned an error."
        }
    }

    private var bannerMessage: String? {
        switch failure {
        case .notSignedIn: "Re-authenticate the account in Settings > Accounts, then try again."
        case .noHostedRemote: "Add a remote in Repository Settings to see its \(feature.noun(on: nil))."
        case .noAccount, .unsupportedHost: nil
        case .forbidden(let message): message.isEmpty ? "Update the token in Settings > Accounts, then try again." : message
        case .other(let message): message
        }
    }

    private var opensAccounts: Bool {
        switch failure {
        case .notSignedIn, .forbidden: true
        default: false
        }
    }

    private var canRetry: Bool {
        if case .unsupportedHost = failure { return false }
        return true
    }
}

#Preview {
    VStack {
        HostUnavailableView(failure: .noAccount(.bitbucket, host: "bitbucket.org"), feature: .pullRequests) {}
        HostUnavailableView(failure: .forbidden("Resource not accessible by personal access token"), feature: .pullRequests) {}
    }
    .frame(width: 600, height: 640)
    .background(Theme.surface)
}
