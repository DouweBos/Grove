// Views/Settings/AccountsViewModel.swift
// Grove

import Foundation
import Observation

/// Settings > Accounts: sign-in state of gh and glab, and the Bitbucket / Azure DevOps accounts.
@MainActor
@Observable
final class AccountsViewModel {

    enum CLIStatus: Equatable {
        case checking
        case missing
        case signedOut
        case signedIn([GitHubCLI.AuthStatus])
        case failed(String)
    }

    private(set) var github: CLIStatus = .checking
    private(set) var gitlab: CLIStatus = .checking
    /// The open "Add Account" sheet.
    private(set) var addition: AddAccountForm?

    let store: HostingAccountStore
    let http: any HTTPClient

    init(store: HostingAccountStore? = nil, http: any HTTPClient = URLSessionHTTPClient()) {
        self.store = store ?? .shared
        self.http = http
    }

    var accounts: [HostingAccount] { store.accounts }

    func check() async {
        github = .checking
        gitlab = .checking
        async let githubStatus = Self.githubStatus()
        async let gitlabStatus = Self.gitlabStatus()
        (github, gitlab) = await (githubStatus, gitlabStatus)
    }

    private static func githubStatus() async -> CLIStatus {
        guard GitHubCLI.isInstalled else { return .missing }
        do {
            let accounts = try await GitHubCLI.authStatus()
            return accounts.isEmpty ? .signedOut : .signedIn(accounts)
        } catch GitHubCLI.Failure.notAuthenticated {
            return .signedOut
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func gitlabStatus() async -> CLIStatus {
        guard GitLabCLI.isInstalled else { return .missing }
        let accounts = await GitLabCLI.authStatus()
        return accounts.isEmpty ? .signedOut : .signedIn(accounts)
    }

    // MARK: REST accounts

    func beginAdding(_ kind: HostingServiceKind = .bitbucket) {
        addition = AddAccountForm(kind: kind)
    }

    func cancelAdding() { addition = nil }

    func remove(_ account: HostingAccount) { store.remove(account) }

    func updateForm(_ change: (inout AddAccountForm) -> Void) {
        guard var form = addition else { return }
        change(&form)
        form.error = nil
        addition = form
    }

    /// Checks the token with a read-only request before keeping it.
    func submitAddition() async {
        guard var form = addition, form.canSubmit else { return }
        form.isVerifying = true
        form.error = nil
        addition = form
        let account = form.account
        do {
            try await HostingAccountVerifier.verify(RESTCredentials(account: account, secret: form.secret), http: http)
            store.add(account, secret: form.secret)
            addition = nil
        } catch {
            form.isVerifying = false
            form.error = error.localizedDescription
            addition = form
        }
    }
}

/// What the "Add Account" sheet collects.
struct AddAccountForm: Equatable {
    var kind: HostingServiceKind
    var username = ""
    var organization = ""
    var secret = ""
    var isVerifying = false
    var error: String?

    var canSubmit: Bool {
        guard !isVerifying, !secret.isEmpty else { return false }
        return kind == .azureDevOps ? !organization.trimmingCharacters(in: .whitespaces).isEmpty
            : !username.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var account: HostingAccount {
        let organization = organization.trimmingCharacters(in: .whitespaces)
        let username = username.trimmingCharacters(in: .whitespaces)
        return HostingAccount(kind: kind, username: username.isEmpty ? organization : username,
                              organization: kind == .azureDevOps ? organization : nil)
    }
}

nonisolated enum HostingAccountVerifier {

    /// A GET the token must be allowed to make: the Bitbucket user, or the Azure organization's projects.
    static func verificationURL(for account: HostingAccount) -> URL? {
        switch account.kind {
        case .bitbucket: URL(string: "\(BitbucketPullRequestHost.api)/user")
        case .azureDevOps: URL(string: "https://dev.azure.com/\(account.organization ?? "")/_apis/projects?$top=1&api-version=7.1")
        case .github, .gitlab: nil
        }
    }

    static func verify(_ credentials: RESTCredentials, http: any HTTPClient) async throws {
        guard let url = verificationURL(for: credentials.account) else {
            throw HostingError.unsupported("\(credentials.account.kind.displayName) signs in through its command-line tool.")
        }
        _ = try await RESTClient(credentials: credentials, http: http).get(url)
    }
}
