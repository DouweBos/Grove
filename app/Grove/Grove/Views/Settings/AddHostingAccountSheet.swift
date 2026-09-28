// Views/Settings/AddHostingAccountSheet.swift
// Grove

import SwiftUI

/// Adds a Bitbucket or Azure DevOps account after checking its token against the service.
struct AddHostingAccountSheet: View {

    let viewModel: AccountsViewModel

    private var form: AddAccountForm { viewModel.addition ?? AddAccountForm(kind: .bitbucket) }

    var body: some View {
        DialogSheet(
            title: "Add \(form.kind.displayName) Account",
            message: message,
            symbol: form.kind.symbol,
            progress: form.isVerifying ? "Checking the token with \(form.kind.displayName)\u{2026}" : nil,
            errorMessage: form.error,
            primaryTitle: "Add Account",
            isPrimaryDisabled: !form.canSubmit,
            onCancel: viewModel.cancelAdding,
            onPrimary: { Task { await viewModel.submitAddition() } }
        ) {
            DialogCard {
                DialogField("Service") {
                    Picker("Service", selection: binding(\.kind)) {
                        Text("Bitbucket").tag(HostingServiceKind.bitbucket)
                        Text("Azure DevOps").tag(HostingServiceKind.azureDevOps)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                if form.kind == .azureDevOps {
                    DialogField("Organization") {
                        TextField("my-org, from dev.azure.com/my-org", text: binding(\.organization))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                DialogField(form.kind == .azureDevOps ? "Name" : "Username") {
                    TextField(form.kind == .azureDevOps ? "Optional label" : "Username, or email for an API token",
                              text: binding(\.username))
                        .textFieldStyle(.roundedBorder)
                }
                DialogField(form.kind == .azureDevOps ? "Access Token" : "App Password") {
                    SecureField(form.kind == .azureDevOps ? "Personal access token" : "App password or API token",
                                text: binding(\.secret))
                        .textFieldStyle(.roundedBorder)
                }
                Button(tokenLinkTitle) { if let url = tokenPage { NSWorkspace.shared.open(url) } }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .padding(.leading, 96 + Theme.Spacing.md)
            }
        }
    }

    private var message: String {
        form.kind == .azureDevOps
            ? "Needs a personal access token with Code (Read & Write) access to the organization."
            : "Needs an app password or API token with Repositories and Pull requests (Read & Write) access."
    }

    private var tokenLinkTitle: String {
        form.kind == .azureDevOps ? "Create a token on dev.azure.com" : "Create an app password on bitbucket.org"
    }

    private var tokenPage: URL? {
        if form.kind == .azureDevOps {
            let organization = form.organization.trimmingCharacters(in: .whitespaces)
            return URL(string: "https://dev.azure.com/\(organization.isEmpty ? "" : organization + "/")_usersSettings/tokens")
        }
        return URL(string: "https://bitbucket.org/account/settings/app-passwords/")
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AddAccountForm, Value>) -> Binding<Value> {
        Binding(get: { form[keyPath: keyPath] }, set: { value in viewModel.updateForm { $0[keyPath: keyPath] = value } })
    }
}

#Preview {
    let viewModel = AccountsViewModel(store: HostingAccountStore(defaults: UserDefaults(suiteName: "preview") ?? .standard))
    viewModel.beginAdding(.azureDevOps)
    return AddHostingAccountSheet(viewModel: viewModel)
}
