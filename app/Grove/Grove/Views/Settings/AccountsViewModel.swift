// Views/Settings/AccountsViewModel.swift
// Grove

import AppKit
import Foundation
import Observation

/// Settings > Accounts: Grove's own accounts, their token checks, signing in and importing CLI logins.
@MainActor
@Observable
final class AccountsViewModel {

    enum Status: Equatable {
        case checking
        case signedIn
        case failed(String)
    }

    private(set) var statuses: [UUID: Status] = [:]
    /// The open add / re-authenticate sheet.
    private(set) var form: AccountForm?
    /// CLI logins with no matching account yet.
    private(set) var importable: [CLITokenImport.Found] = []
    private(set) var importingHost: String?
    private(set) var importError: String?
    @ObservationIgnored private var deviceFlowTask: Task<Void, Never>?

    let store: HostingAccountStore
    let http: any HTTPClient
    /// Where CLI logins come from; tests hand in fixed ones.
    @ObservationIgnored var cliLogins: () async -> [CLITokenImport.Found] = {
        await CLITokenImport.githubLogins() + CLITokenImport.gitlabLogins()
    }

    init(store: HostingAccountStore? = nil, http: any HTTPClient = URLSessionHTTPClient()) {
        self.store = store ?? .shared
        self.http = http
    }

    var accounts: [HostingAccount] { store.accounts }

    // MARK: Checking

    /// Re-checks every token with a read-only call and looks for CLI logins to import.
    func check() async {
        for account in accounts { statuses[account.id] = .checking }
        await withTaskGroup(of: (UUID, Status).self) { group in
            for account in accounts {
                let credentials = store.credentials(for: account)
                let http = http
                group.addTask {
                    guard let credentials else { return (account.id, .failed("No token in the Keychain.")) }
                    do {
                        _ = try await HostingAccountVerifier.whoAmI(credentials, http: http)
                        return (account.id, .signedIn)
                    } catch {
                        return (account.id, .failed(error.localizedDescription))
                    }
                }
            }
            for await (id, status) in group { statuses[id] = status }
        }
        await scanCLIs()
    }

    private func scanCLIs() async {
        let found = await cliLogins()
        importable = found.filter { login in !accounts.contains { $0.kind == login.kind && $0.host == login.host.lowercased() } }
    }

    // MARK: Importing

    /// Checks the CLI's token like a typed one and keeps a copy in Grove's Keychain item; the CLI is left untouched.
    func importLogin(_ login: CLITokenImport.Found) async {
        importingHost = login.host
        importError = nil
        defer { importingHost = nil }
        let draft = HostingAccount(kind: login.kind, host: login.host, username: "")
        do {
            let username = try await HostingAccountVerifier.whoAmI(RESTCredentials(account: draft, secret: login.token), http: http)
            let account = HostingAccount(kind: login.kind, host: login.host, username: username)
            store.add(account, secret: login.token)
            statuses[store.accounts.first { $0.kind == account.kind && $0.host == account.host && $0.username == username }?.id ?? account.id]
                = .signedIn
            importable.removeAll { $0 == login }
        } catch {
            importError = "\(login.host): \(error.localizedDescription)"
        }
    }

    // MARK: Adding and re-authenticating

    func beginAdding(_ provider: AccountProvider) {
        form = AccountForm(provider: provider)
    }

    func beginReauthenticating(_ account: HostingAccount) {
        var form = AccountForm(provider: .matching(account))
        form.host = account.host
        form.username = account.username
        form.organization = account.organization ?? ""
        form.replacing = account.id
        self.form = form
    }

    func cancelForm() {
        deviceFlowTask?.cancel()
        deviceFlowTask = nil
        form = nil
    }

    func remove(_ account: HostingAccount) {
        store.remove(account)
        statuses[account.id] = nil
    }

    func updateForm(_ change: (inout AccountForm) -> Void) {
        guard var form else { return }
        change(&form)
        form.error = nil
        self.form = form
    }

    /// Checks the token with a read-only "who am I" before keeping it.
    func submitForm() async {
        guard var form, form.canSubmit else { return }
        form.isVerifying = true
        self.form = form
        await save(token: form.token.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func save(token: String) async {
        guard var form else { return }
        let draft = form.account(username: form.username)
        do {
            let username = try await HostingAccountVerifier.whoAmI(RESTCredentials(account: draft, secret: token), http: http)
            let account = form.account(username: username)
            store.add(account, secret: token)
            statuses[account.id] = .signedIn
            if let refreshed = store.accounts.first(where: { $0.host == account.host && $0.username == username }) {
                statuses[refreshed.id] = .signedIn
            }
            self.form = nil
        } catch {
            form.isVerifying = false
            form.error = error.localizedDescription
            self.form = form
        }
    }

    // MARK: Browser sign-in

    /// OAuth device flow: shows a code, opens the approval page, then waits for the token.
    func startBrowserSignIn() {
        guard let form, OAuthDeviceFlow.isAvailable(for: form.provider) else { return }
        let (provider, host, http) = (form.provider, form.host, http)
        deviceFlowTask = Task { [weak self] in
            do {
                let code = try await OAuthDeviceFlow.start(provider, host: host, http: http)
                self?.updateForm { $0.deviceCode = code }
                NSWorkspace.shared.open(code.verificationURL)
                var interval = UInt64(code.interval)
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: interval * 1_000_000_000)
                    switch try await OAuthDeviceFlow.poll(provider, host: host, code: code, http: http) {
                    case .pending: continue
                    case .slowDown: interval += 5
                    case .token(let token):
                        self?.updateForm { $0.isVerifying = true }
                        await self?.save(token: token)
                        return
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                self?.updateForm { $0.deviceCode = nil }
                self?.form?.error = error.localizedDescription
            }
        }
    }
}

/// What the add / re-authenticate sheet collects.
struct AccountForm: Equatable {
    var provider: AccountProvider {
        didSet { if provider != oldValue { host = provider.asksForHost ? "" : provider.kind.defaultHost } }
    }
    var host: String
    var username = ""
    var organization = ""
    var token = ""
    /// The account being re-authenticated.
    var replacing: UUID?
    var isVerifying = false
    var error: String?
    var deviceCode: OAuthDeviceFlow.Code?

    init(provider: AccountProvider) {
        self.provider = provider
        host = provider.asksForHost ? "" : provider.kind.defaultHost
    }

    var trimmedHost: String {
        var value = host.trimmingCharacters(in: .whitespaces).lowercased()
        for scheme in ["https://", "http://"] where value.hasPrefix(scheme) { value = String(value.dropFirst(scheme.count)) }
        return value.split(separator: "/").first.map(String.init) ?? value
    }

    var canSubmit: Bool {
        guard !isVerifying, !token.trimmingCharacters(in: .whitespaces).isEmpty, !trimmedHost.isEmpty else { return false }
        if provider == .azureDevOps { return !organization.trimmingCharacters(in: .whitespaces).isEmpty }
        if provider.asksForUsername { return !username.trimmingCharacters(in: .whitespaces).isEmpty }
        return true
    }

    func account(username: String) -> HostingAccount {
        let organization = organization.trimmingCharacters(in: .whitespaces)
        return HostingAccount(id: replacing ?? UUID(), kind: provider.kind, host: trimmedHost,
                              username: username.trimmingCharacters(in: .whitespaces),
                              organization: provider == .azureDevOps ? organization : nil)
    }
}
