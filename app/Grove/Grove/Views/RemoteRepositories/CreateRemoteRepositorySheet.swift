// Views/RemoteRepositories/CreateRemoteRepositorySheet.swift
// Grove

import SwiftUI

/// Creates an empty repository on a service, then offers to clone it or add it as a remote.
struct CreateRemoteRepositorySheet: View {

    @Environment(WindowViewModel.self) private var windowVM
    let viewModel: CreateRemoteRepositoryViewModel

    var body: some View {
        switch viewModel.phase {
        case .editing, .creating: form
        case .created(let repository): created(repository)
        }
    }

    // MARK: Form

    private var form: some View {
        DialogSheet(
            title: "New Remote Repository",
            message: "Creates an empty repository on \(viewModel.section?.account.kind.displayName ?? "the service").",
            symbol: "plus.rectangle.on.folder",
            width: 500,
            progress: viewModel.phase == .creating ? "Creating \(viewModel.trimmedName)\u{2026}" : nil,
            errorMessage: viewModel.errorMessage,
            primaryTitle: "Create",
            isPrimaryDisabled: !viewModel.canCreate,
            onCancel: windowVM.remoteRepositories.endCreating,
            onPrimary: { Task { await viewModel.create() } }
        ) {
            DialogCard {
                if viewModel.sections.count > 1 {
                    DialogField("Account") {
                        Picker("Account", selection: Binding(get: { viewModel.accountID }, set: viewModel.selectAccount)) {
                            ForEach(viewModel.sections) { section in
                                Text("\(section.account.kind.displayName) \u{00B7} \(section.account.title)").tag(section.id)
                            }
                        }
                        .labelsHidden()
                    }
                }
                DialogField(viewModel.section?.account.kind == .azureDevOps ? "Project" : "Owner") {
                    Picker("Owner", selection: Binding(get: { viewModel.ownerID }, set: viewModel.selectOwner)) {
                        ForEach(viewModel.owners) { owner in
                            Label(owner.title, systemImage: owner.isAccount ? "person.crop.circle" : "building.2").tag(owner.id)
                        }
                    }
                    .labelsHidden()
                }
                DialogField("Name") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        TextField("my-repository", text: Binding(get: { viewModel.name }, set: viewModel.setName))
                            .textFieldStyle(.roundedBorder)
                            .font(.monoCaption)
                        if !viewModel.trimmedName.isEmpty, !viewModel.isNameValid {
                            Text("Use letters, digits, dots, dashes and underscores.")
                                .font(.system(size: 11)).foregroundStyle(Theme.danger)
                        }
                    }
                }
                if viewModel.supportsVisibilityAndDescription {
                    DialogField("Description") {
                        TextField("Optional", text: Binding(get: { viewModel.details }, set: viewModel.setDetails))
                            .textFieldStyle(.roundedBorder)
                    }
                    DialogOptionRow(isOn: Binding(get: { viewModel.isPrivate }, set: viewModel.setPrivate), label: "Private",
                                    description: "Only people you give access can see it.")
                        .padding(.leading, 96 + Theme.Spacing.md)
                } else {
                    Text("Azure DevOps repositories take their visibility from the project.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                        .padding(.leading, 96 + Theme.Spacing.md)
                }
            }
        }
    }

    // MARK: Created

    private func created(_ repository: RemoteRepository) -> some View {
        DialogSheet(
            title: "Created \(repository.name)",
            message: "\(repository.nameWithOwner) is ready on \(repository.service.displayName). It's empty until something is pushed to it.",
            symbol: "checkmark.circle",
            width: 500,
            primaryTitle: "Clone\u{2026}",
            cancelTitle: "Done",
            onCancel: windowVM.remoteRepositories.endCreating,
            onPrimary: {
                windowVM.remoteRepositories.endCreating()
                windowVM.showCloneDialog(url: repository.sshURL.isEmpty ? repository.httpsCloneURL : repository.sshURL)
            }
        ) {
            DialogCard {
                DialogField("SSH") { urlText(repository.sshURL) }
                DialogField("HTTPS") { urlText(repository.httpsCloneURL) }
            }
            if !viewModel.targets.isEmpty { addRemote }
        }
    }

    private var addRemote: some View {
        DialogCard {
            SectionLabel(title: "Add as a Remote")
            DialogField("Repository") {
                Picker("Repository", selection: Binding(get: { viewModel.targetPath ?? "" }, set: viewModel.selectTarget)) {
                    ForEach(viewModel.targets) { Text($0.name).tag($0.path) }
                }
                .labelsHidden()
            }
            DialogField("Remote Name") {
                HStack(spacing: Theme.Spacing.sm) {
                    TextField("origin", text: Binding(get: { viewModel.remoteName }, set: viewModel.setRemoteName))
                        .textFieldStyle(.roundedBorder)
                        .font(.monoCaption)
                    if viewModel.isAddingRemote { ProgressView().controlSize(.small) }
                    Button("Add Remote") { Task { await viewModel.addAsRemote() } }
                        .disabled(!viewModel.canAddRemote)
                }
            }
            if let added = viewModel.addedRemote {
                StatusBadge(title: "Added as \u{201C}\(added)\u{201D}", symbol: "checkmark.circle.fill", tone: .positive)
                    .padding(.leading, 96 + Theme.Spacing.md)
            }
            if let error = viewModel.remoteError {
                Banner(symbol: "xmark.octagon", message: error, tone: .negative)
            }
        }
    }

    private func urlText(_ url: String) -> some View {
        Text(url).font(.monoCaption).foregroundStyle(Theme.textPrimary).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
    }
}

#Preview {
    let account = CatalogAccount(id: "gh", kind: .github, host: "github.com", title: "me")
    let owner = RemoteRepositoryOwner(login: "me", isAccount: true, accountID: "gh")
    let section = RemoteRepositoriesViewModel.Section(catalog: GitHubCatalog(login: account.title), owners: [owner])
    return CreateRemoteRepositorySheet(viewModel: CreateRemoteRepositoryViewModel(sections: { [section] }, owner: owner, targets: [],
                                                                                   preferredTarget: nil))
        .environment(WindowViewModel(manager: MockRepositoryManager()))
}
