// Views/Settings/RepositorySettingsView.swift
// Grove
//
// Settings scoped to the open repository, backed by `git config --local`.

import GroveKit
import SwiftUI

struct RepositorySettingsView: View {

    /// Owned by the session so revisits show the last values and any unsaved draft.
    let viewModel: RepositorySettingsViewModel
    private var repository: any GitRepositoryProtocol { viewModel.repository }
    private var profiles: [UserProfile] { UserProfileStore.shared.profiles }
    @State private var remoteToRemove: String?

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Repository Settings", detail: ".git/config") {
                if viewModel.isLoading { ProgressView().controlSize(.small) }
                if viewModel.didSave && !viewModel.hasChanges {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.success)
                }
                Button("Revert") { viewModel.revert() }
                    .disabled(!viewModel.hasChanges || viewModel.isSaving)
                Button("Save") { Task { await viewModel.save() } }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!viewModel.hasChanges || viewModel.isSaving)
            }
            .controlSize(.small)
            if let error = viewModel.errorMessage {
                Banner(symbol: "xmark.octagon", message: error, tone: .negative, onDismiss: viewModel.dismissError)
                    .padding([.horizontal, .top], Theme.Spacing.md)
            }
            form
        }
        .frame(maxWidth: 720, maxHeight: .infinity, alignment: .top)
        .panel()
        .frame(maxWidth: .infinity)
        .padding(.bottom, Theme.Spacing.md)
        .task { await viewModel.load() }
        .confirmationDialog(
            "Remove remote \u{201C}\(remoteToRemove ?? "")\u{201D}?",
            isPresented: Binding(get: { remoteToRemove != nil }, set: { if !$0 { remoteToRemove = nil } }),
            presenting: remoteToRemove
        ) { name in
            Button("Remove Remote", role: .destructive) { Task { await viewModel.removeRemote(name) } }
        } message: { _ in
            Text("Grove forgets the remote and its remote branches. Nothing on the server changes.")
        }
    }

    private var form: some View {
        Form {
            Section {
                if !profiles.isEmpty {
                    Picker("Profile", selection: Binding(get: { viewModel.matchingProfile(in: profiles)?.id },
                                                         set: { id in profiles.first { $0.id == id }.map(viewModel.applyProfile) })) {
                        Text("Custom").tag(UserProfile.ID?.none)
                        ForEach(profiles) { Text("\($0.title) \u{2014} \($0.email)").tag(Optional($0.id)) }
                    }
                }
                TextField("Name", text: Binding(get: { viewModel.draft.userName }, set: viewModel.setUserName),
                          prompt: Text("Use global name"))
                TextField("Email", text: Binding(get: { viewModel.draft.userEmail }, set: viewModel.setUserEmail),
                          prompt: Text("Use global email"))
                TextField("Signing Key", text: Binding(get: { viewModel.draft.userSigningKey }, set: viewModel.setUserSigningKey),
                          prompt: Text("Use global signing key"))
                    .font(.monoCaption)
            } header: {
                Text("Commit Identity")
            } footer: {
                Text("Overrides your global identity for commits in this repository only. Leave empty to use the global value. "
                     + "Profiles are managed in Settings.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }

            Section("Pulling") {
                Picker("When pulling", selection: Binding(get: { viewModel.draft.pullStrategy }, set: viewModel.setPullStrategy)) {
                    ForEach(RepositorySettingsViewModel.PullStrategy.allCases) { Text($0.title).tag($0) }
                }
            }

            Section {
                EnvironmentVariablesEditor(variables: Binding(get: { viewModel.draft.environment }, set: viewModel.setEnvironment))
            } header: {
                Text("Environment Variables")
            } footer: {
                Text("Passed to every git command Grove runs here, and so to hooks, on top of the global ones in Settings.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }

            Section("Remotes") {
                if viewModel.remoteNames.isEmpty {
                    Text("This repository has no remotes.").foregroundStyle(Theme.textSecondary)
                }
                ForEach(viewModel.remoteNames, id: \.self) { name in
                    HStack {
                        TextField(name, text: Binding(get: { viewModel.draft.remoteURLs[name] ?? "" },
                                                      set: { viewModel.setRemoteURL($0, for: name) }))
                            .font(.monoCaption)
                        Button("Remove \(name)", systemImage: "minus.circle") { remoteToRemove = name }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Remove \u{201C}\(name)\u{201D}")
                    }
                }
                Button("Add Remote\u{2026}", systemImage: "plus") { viewModel.requestAddRemote() }
                    .disabled(!viewModel.hasLoaded)
            }

            Section("Repository") {
                LabeledContent("Location") {
                    Text(repository.path.path)
                        .font(.monoCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let branch = repository.currentBranch {
                    LabeledContent("Current branch") {
                        Text(branch.name).font(.monoCaption).foregroundStyle(Theme.textSecondary)
                    }
                }
                LabeledContent("State") {
                    Text(stateDescription).foregroundStyle(Theme.textSecondary)
                }
                HStack {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([repository.path])
                    }
                    Button("Open in \(GrovePreferences.terminalApp.rawValue)") {
                        try? ExternalToolLauncher.openInTerminal(repository.path)
                    }
                    Button("Open in Editor") {
                        try? ExternalToolLauncher.openInEditor([repository.path])
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .disabled(!viewModel.hasLoaded)
    }

    private var stateDescription: String {
        switch repository.repositoryState {
        case .normal: "Clean"
        case .merge: "Merging"
        case .rebase, .rebaseInteractive: "Rebasing"
        case .revert: "Reverting"
        case .cherrypick: "Cherry-picking"
        case .bisect: "Bisecting"
        }
    }
}

#Preview {
    RepositorySettingsView(viewModel: RepositorySettingsViewModel(repository: MockGitRepository()))
        .frame(width: 800, height: 640)
        .padding()
        .background(Theme.background)
}
