// Views/Settings/SigningPreferencesTab.swift
// Grove
//
// Which key git signs with, a test signature, and 1Password's SSH agent and signer for git run by Grove.

import SwiftUI

@MainActor
@Observable
final class SigningPreferencesModel {

    enum TestState: Equatable {
        case idle, running
        case passed(String)
        case failed(String)
    }

    private(set) var config = SigningConfig()
    private(set) var testState = TestState.idle
    private(set) var agentAvailable = GitEnvironment.isOnePasswordAgentAvailable
    private(set) var signerInstalled = GitEnvironment.isOnePasswordSignerInstalled

    func load() async {
        agentAvailable = GitEnvironment.isOnePasswordAgentAvailable
        signerInstalled = GitEnvironment.isOnePasswordSignerInstalled
        config = await SigningInspector.load()
    }

    func testSigning() async {
        testState = .running
        do {
            let status = try await SigningInspector.testSign()
            testState = .passed(SigningInspector.describe(signatureStatus: status))
        } catch {
            testState = .failed(error.localizedDescription)
        }
    }
}

struct SigningPreferencesTab: View {

    @State private var model = SigningPreferencesModel()
    @AppStorage(GitEnvironment.Key.useOnePasswordAgent) private var useOnePasswordAgent = false
    @AppStorage(GitEnvironment.Key.useOnePasswordSigning) private var useOnePasswordSigning = false

    var body: some View {
        Form {
            signingSection
            onePasswordSection
        }
        .formStyle(.grouped)
        .task { await model.load() }
        .onChange(of: useOnePasswordSigning) { _, _ in Task { await model.load() } }
    }

    private var signingSection: some View {
        Section {
            LabeledContent("Format", value: model.config.formatTitle)
            LabeledContent("Signing key") {
                mono(model.config.signingKey ?? (model.config.format == "openpgp" ? "Chosen by committer email" : "Not set"))
            }
            LabeledContent("Program") { mono(model.config.program ?? model.config.defaultProgram) }
            LabeledContent("Sign commits", value: model.config.signsCommits ? "Always" : "When chosen in the composer")
            LabeledContent("Sign tags", value: model.config.signsTags ? "Always" : "When chosen")
            if model.config.format == "ssh" {
                LabeledContent("Allowed signers") { mono(model.config.allowedSignersFile ?? "Not set, so signatures show unverified") }
            }
            HStack {
                Button("Test Signing") { Task { await model.testSigning() } }
                    .disabled(model.testState == .running)
                testResult
            }
        } header: {
            Text("Commit Signing")
        } footer: {
            Text("From your global git config (gpg.format, user.signingkey, commit.gpgsign). The test signs a commit in a temporary "
                 + "repository and deletes it; a repository's own signing key is set in its Settings.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    @ViewBuilder
    private var testResult: some View {
        switch model.testState {
        case .idle: EmptyView()
        case .running: ProgressView().controlSize(.small)
        case .passed(let message):
            Label(message, systemImage: "checkmark.seal.fill").foregroundStyle(Theme.success).font(.caption)
        case .failed(let message):
            Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(Theme.danger).font(.caption).lineLimit(3)
        }
    }

    private var onePasswordSection: some View {
        Section {
            LabeledContent("SSH agent") {
                Label(model.agentAvailable ? "Found" : "Not running", systemImage: model.agentAvailable ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(model.agentAvailable ? Theme.success : Theme.textSecondary)
            }
            Toggle("Use the 1Password SSH agent for fetch, pull and push", isOn: $useOnePasswordAgent)
                .disabled(!model.agentAvailable && !useOnePasswordAgent)
            Toggle("Sign with 1Password (op-ssh-sign)", isOn: $useOnePasswordSigning)
                .disabled(!model.signerInstalled && !useOnePasswordSigning)
            if !model.signerInstalled {
                Text("1Password isn't installed in /Applications.").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("1Password")
        } footer: {
            Text("Applies to git run by Grove only: SSH_AUTH_SOCK points at 1Password's agent, and signing uses SSH format with "
                 + "op-ssh-sign. Set user.signingkey to the public key 1Password shows. Your git and SSH config files aren't changed.")
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private func mono(_ text: String) -> some View {
        Text(text).font(.monoCaption).foregroundStyle(Theme.textSecondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
    }
}

#Preview {
    SigningPreferencesTab().frame(width: 560, height: 560)
}
