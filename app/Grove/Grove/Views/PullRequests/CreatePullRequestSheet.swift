// Views/PullRequests/CreatePullRequestSheet.swift
// Grove

import SwiftUI

/// Opens a pull request from a head branch into a base branch on the host.
struct CreatePullRequestSheet: View {

    let viewModel: CreatePullRequestViewModel
    let onCancel: () -> Void

    var body: some View {
        DialogSheet(
            title: "Create Pull Request",
            message: "Asks to merge \(viewModel.head) into \(viewModel.base.isEmpty ? "the base branch" : viewModel.base).",
            symbol: "arrow.triangle.pull",
            width: 560,
            progress: viewModel.progressTitle,
            errorMessage: viewModel.errorMessage,
            primaryTitle: viewModel.isDraft ? "Create Draft" : "Create",
            isPrimaryDisabled: !viewModel.canSubmit,
            onCancel: onCancel,
            onPrimary: { Task { await viewModel.submit() } }
        ) {
            DialogCard {
                DialogField("Head") {
                    Picker("Head", selection: Binding(get: { viewModel.head },
                                                      set: { name in Task { await viewModel.setHead(name) } })) {
                        ForEach(viewModel.headCandidates, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                }
                DialogField("Base") {
                    Picker("Base", selection: Binding(get: { viewModel.base },
                                                      set: { name in Task { await viewModel.setBase(name) } })) {
                        ForEach(viewModel.baseCandidates, id: \.self) { Text("\(viewModel.remote)/\($0)").tag($0) }
                    }
                    .labelsHidden()
                }
                summary
            }
            DialogCard {
                DialogField("Title") {
                    TextField("Title", text: Binding(get: { viewModel.title }, set: viewModel.setTitle))
                        .textFieldStyle(.roundedBorder)
                }
                DialogField("Description") {
                    MultilineField(text: viewModel.body, placeholder: "Describe the change (Markdown)", height: 150,
                                   onChange: viewModel.setBody)
                }
                DialogField("Reviewers") {
                    TextField("Optional, e.g. alice, bob", text: Binding(get: { viewModel.reviewersText },
                                                                         set: viewModel.setReviewers))
                        .textFieldStyle(.roundedBorder)
                        .font(.monoCaption)
                }
                DialogOptionRow(isOn: Binding(get: { viewModel.isDraft }, set: viewModel.setDraft),
                                label: "Draft",
                                description: "Reviewers aren't asked yet and it can't be merged until marked ready.")
                .padding(.leading, 96 + Theme.Spacing.md)
            }
        }
        .task { await viewModel.load() }
        .confirmationDialog(pushTitle, isPresented: Binding(get: { viewModel.isConfirmingPush },
                                                            set: { if !$0 { viewModel.cancelPush() } })) {
            Button("Push and Create") { Task { await viewModel.confirmPush() } }
            Button("Cancel", role: .cancel) { viewModel.cancelPush() }
        } message: {
            Text(pushMessage)
        }
    }

    private var summary: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if viewModel.isLoadingCommits {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "clock").foregroundStyle(Theme.textSecondary)
                Text(commitCount).font(.monoCaption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            switch viewModel.publishState {
            case .published:
                EmptyView()
            case .unpublished:
                StatusBadge(title: "Not on \(viewModel.remote) yet", symbol: "icloud.slash", tone: .caution)
            case .unpushed(let count):
                StatusBadge(title: "\(count) unpushed", symbol: "arrow.up.circle", tone: .caution)
            }
        }
        .padding(.leading, 96 + Theme.Spacing.md)
    }

    private var commitCount: String {
        let count = viewModel.commits.count
        return count == 1 ? "1 commit" : "\(count) commits"
    }

    private var pushTitle: String {
        viewModel.publishState == .unpublished ? "Publish \(viewModel.head) first?" : "Push \(viewModel.head) first?"
    }

    private var pushMessage: String {
        switch viewModel.publishState {
        case .unpushed(let count):
            "\(count) commit\(count == 1 ? " isn't" : "s aren't") on \(viewModel.remote) yet. Grove pushes them, then creates the pull request."
        default:
            "The branch isn't on \(viewModel.remote) yet. Grove pushes it as \(viewModel.remote)/\(viewModel.remoteHead) "
                + "and tracks it, then creates the pull request."
        }
    }
}

#Preview {
    let repo = MockGitRepository()
    let refs = RepositoryRefs(repository: repo)
    refs.replace(localBranches: MockData.branches.filter(\.isLocal))
    refs.replace(remoteBranches: MockData.branches.filter(\.isRemote), remotes: MockData.remotes)
    return CreatePullRequestSheet(viewModel: CreatePullRequestViewModel(repository: repo, refs: refs, head: "feature/auth")) {}
}
