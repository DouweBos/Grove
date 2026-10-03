// Views/Settings/AddHostingAccountSheet.swift
// Grove

import GroveKit
import SwiftUI

/// Adds or re-authenticates an account: a browser sign-in where the service has one, else a token, checked before saving.
struct AddHostingAccountSheet: View {

    let viewModel: AccountsViewModel

    private var form: AccountForm { viewModel.form ?? AccountForm(provider: .github) }
    private var provider: AccountProvider { form.provider }

    var body: some View {
        DialogSheet(
            title: form.replacing == nil ? "Add \(provider.title) Account" : "Sign In to \(provider.title) Again",
            message: "Grove checks the token with \(provider.title) before saving it in your Keychain.",
            symbol: provider.kind.symbol,
            width: 520,
            progress: form.isVerifying ? "Checking the token\u{2026}" : nil,
            errorMessage: form.error,
            primaryTitle: form.replacing == nil ? "Add Account" : "Save",
            isPrimaryDisabled: !form.canSubmit,
            onCancel: viewModel.cancelForm,
            onPrimary: { Task { await viewModel.submitForm() } }
        ) {
            DialogCard {
                DialogField("Service") {
                    Picker("Service", selection: binding(\.provider)) {
                        ForEach(AccountProvider.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .disabled(form.replacing != nil)
                }
                if provider.asksForHost {
                    DialogField("Host") {
                        TextField(provider.kind == .github ? "github.example.com" : "gitlab.example.com", text: binding(\.host))
                            .textFieldStyle(.roundedBorder)
                            .font(.monoCaption)
                    }
                }
                if provider == .azureDevOps {
                    DialogField("Organization") {
                        TextField("my-org, from dev.azure.com/my-org", text: binding(\.organization))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                if provider.asksForUsername || provider == .azureDevOps {
                    DialogField(provider == .azureDevOps ? "Name" : "Username") {
                        TextField(provider == .azureDevOps ? "Optional label" : "Username, or email for an API token",
                                  text: binding(\.username))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                if OAuthDeviceFlow.isAvailable(for: provider) { browserSignIn }
                DialogField(provider == .bitbucket ? "App Password" : "Token") {
                    SecureField(provider == .bitbucket ? "App password or API token" : "Personal access token", text: binding(\.token))
                        .textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Button(form.trimmedHost.isEmpty ? "Enter the host to open its token page" : "Create a token on \(form.trimmedHost)") {
                        if let url = provider.tokenPage(host: form.trimmedHost, organization: form.organization) { NSWorkspace.shared.open(url) }
                    }
                    .buttonStyle(.link)
                    .disabled(form.trimmedHost.isEmpty)
                    Text("Needs: \(provider.scopes)").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12))
                .padding(.leading, 96 + Theme.Spacing.md)
            }
        }
    }

    @ViewBuilder
    private var browserSignIn: some View {
        DialogField("Browser") {
            if let code = form.deviceCode {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView().controlSize(.small)
                    Text("Enter").foregroundStyle(Theme.textSecondary)
                    Text(code.userCode).font(.monoCaption).textSelection(.enabled)
                    Button("Open Page") { NSWorkspace.shared.open(code.verificationURL) }
                }
            } else {
                Button("Sign In with Browser\u{2026}", action: viewModel.startBrowserSignIn)
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AccountForm, Value>) -> Binding<Value> {
        Binding(get: { form[keyPath: keyPath] }, set: { value in viewModel.updateForm { $0[keyPath: keyPath] = value } })
    }
}

#Preview {
    let viewModel = AccountsViewModel(store: HostingAccountStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
    viewModel.beginAdding(.githubEnterprise)
    return AddHostingAccountSheet(viewModel: viewModel)
}
