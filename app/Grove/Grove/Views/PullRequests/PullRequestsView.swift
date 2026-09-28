// Views/PullRequests/PullRequestsView.swift
// Grove

import SwiftUI

/// Pull request list on the left, the selected PR on the right. Data comes from the `gh` CLI.
struct PullRequestsView: View {

    @Environment(PullRequestsViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            PullRequestListPanel()
                .frame(width: 360)
            if let failure = viewModel.loadFailure, viewModel.pullRequests.isEmpty {
                PRUnavailableView(failure: failure)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .panel()
            } else {
                PullRequestDetailView()
            }
        }
        .padding(.bottom, Theme.Spacing.md)
        .confirmationDialog(dialogTitle, isPresented: Binding(get: { viewModel.pendingOperation != nil },
                                                              set: { if !$0 { viewModel.cancelPendingOperation() } }),
                            titleVisibility: .visible, presenting: viewModel.pendingOperation) { pending in
            Button(pending.operation == .merge ? "Merge on GitHub" : "Close Pull Request",
                   role: pending.operation == .close ? .destructive : nil) {
                Task { await viewModel.confirm(pending) }
            }
            Button("Cancel", role: .cancel) { viewModel.cancelPendingOperation() }
        } message: { pending in
            Text(pending.operation == .merge
                 ? "Creates a merge commit of \(pending.pr.sourceBranch) into \(pending.pr.targetBranch) on GitHub."
                 : "Closes #\(String(pending.pr.id)) without merging. You can reopen it on GitHub.")
        }
        .alert("Pull Request Action Failed", isPresented: Binding(get: { viewModel.actionError != nil },
                                                                 set: { if !$0 { viewModel.clearActionError() } })) {
            Button("OK") { viewModel.clearActionError() }
        } message: {
            Text(viewModel.actionError ?? "")
        }
    }

    private var dialogTitle: String {
        guard let pending = viewModel.pendingOperation else { return "" }
        return pending.operation == .merge ? "Merge #\(pending.pr.id)?" : "Close #\(pending.pr.id)?"
    }
}

// MARK: - Unavailable

private struct PRUnavailableView: View {
    @Environment(PullRequestsViewModel.self) private var viewModel
    let failure: PRLoadFailure

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "arrow.triangle.pull")
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
                .padding(.bottom, Theme.Spacing.sm)
            Banner(symbol: "exclamationmark.triangle", message: bannerMessage,
                   actionTitle: actionTitle, action: action)
                .frame(maxWidth: 560)
            Button("Try Again") { Task { await viewModel.refresh() } }
                .disabled(viewModel.isLoading)
        }
        .padding(Theme.Spacing.xl)
    }

    private var title: String {
        switch failure {
        case .ghMissing: "GitHub CLI Needed"
        case .notAuthenticated: "Sign In to GitHub"
        case .noGitHubRemote: "No GitHub Remote"
        case .other: "Couldn't Load Pull Requests"
        }
    }

    private var subtitle: String {
        switch failure {
        case .ghMissing: "Grove reads pull requests through the gh command-line tool."
        case .notAuthenticated: "gh is installed but not signed in to github.com."
        case .noGitHubRemote: "None of this repository's remotes point at GitHub."
        case .other: "gh returned an error."
        }
    }

    private var bannerMessage: String {
        switch failure {
        case .ghMissing: "Install it with Homebrew: brew install gh"
        case .notAuthenticated: "Run \u{201C}gh auth login\u{201D} in Terminal, then try again."
        case .noGitHubRemote: "Add a GitHub remote in Repository Settings to see its pull requests."
        case .other(let message): message
        }
    }

    private var actionTitle: String? {
        switch failure {
        case .ghMissing: "Open cli.github.com"
        case .notAuthenticated: "Open Terminal"
        case .noGitHubRemote, .other: nil
        }
    }

    private var action: (() -> Void)? {
        switch failure {
        case .ghMissing: { NSWorkspace.shared.open(URL(string: "https://cli.github.com")!) }
        case .notAuthenticated: { try? ExternalToolLauncher.openInTerminal(viewModel.repository.path) }
        case .noGitHubRemote, .other: nil
        }
    }
}

// MARK: - List Panel

private struct PullRequestListPanel: View {
    @Environment(PullRequestsViewModel.self) private var viewModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Pull Requests", detail: "\(viewModel.filteredPullRequests.count)") {
                if viewModel.isLoading { ProgressView().controlSize(.small) }
                Button { viewModel.beginCreatePullRequest() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("Create Pull Request")
                Button { Task { await viewModel.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Reload from GitHub")
            }
            VStack(spacing: Theme.Spacing.sm) {
                Picker("Filter", selection: Binding(get: { viewModel.filterState }, set: viewModel.setFilter)) {
                    ForEach(PRFilterState.allCases, id: \.self) { filter in
                        Text("\(filter.rawValue) \(viewModel.count(for: filter))").tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                PanelSearchField(placeholder: "Filter by title, author, branch", text: viewModel.searchText,
                                 onChange: viewModel.setSearchText)
            }
            .padding([.horizontal, .top], Theme.Spacing.sm)
            content
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .panel()
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasLoaded {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.loadFailure != nil && viewModel.pullRequests.isEmpty {
            EmptyStateView(systemImage: "exclamationmark.triangle", title: "Not Available")
        } else if viewModel.filteredPullRequests.isEmpty {
            EmptyStateView(systemImage: "arrow.triangle.pull", title: emptyTitle,
                           subtitle: viewModel.pullRequests.isEmpty ? "This repository has no pull requests on GitHub." : nil)
        } else {
            SelectableList(items: viewModel.filteredPullRequests, selection: viewModel.selectedPR?.id,
                           onSelect: { pr in Task { await viewModel.select(pr) } }) { pr in
                PullRequestRow(pr: pr)
                    .contextMenu {
                        Button("Open on GitHub", systemImage: "safari") { viewModel.openInBrowser(pr) }
                        Button("Check Out Branch", systemImage: "arrow.down.to.line") { Task { await viewModel.checkout(pr) } }
                        Button("Copy Branch Name", systemImage: "doc.on.doc") { GroveClipboard.copy(pr.sourceBranch) }
                    }
            }
        }
    }

    private var emptyTitle: String {
        viewModel.searchText.isEmpty ? "No \(viewModel.filterState.rawValue) Pull Requests" : "No Matches"
    }
}

struct PullRequestRow: View {
    let pr: PullRequestInfo

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: pr.stateSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(pr.stateColor)
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(pr.title)
                    .font(.rowTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: Theme.Spacing.sm) {
                    Text(verbatim: "#\(pr.id)")
                    Text(pr.authorName).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(pr.updatedDate, format: .relative(presentation: .named))
                }
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
            }
            if pr.checksStatus != .none {
                Image(systemName: pr.checksStatus.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(pr.checksStatus.color)
                    .padding(.top, 1)
            }
        }
    }
}

extension PullRequestInfo {
    var stateSymbol: String {
        if isDraft && state == .open { return "circle.dashed" }
        switch state {
        case .open: return "arrow.triangle.pull"
        case .merged: return "arrow.triangle.merge"
        case .closed: return "xmark.circle"
        }
    }

    var stateColor: Color {
        if isDraft && state == .open { return Theme.textSecondary }
        switch state {
        case .open: return Theme.success
        case .merged: return Theme.renamed
        case .closed: return Theme.danger
        }
    }
}

extension PRChecksStatus {
    var symbol: String {
        switch self {
        case .passing: "checkmark.circle.fill"
        case .failing: "xmark.circle.fill"
        case .pending: "clock.fill"
        case .none: "minus.circle"
        }
    }

    var color: Color {
        switch self {
        case .passing: Theme.success
        case .failing: Theme.danger
        case .pending: Theme.warning
        case .none: Theme.textSecondary
        }
    }
}

#Preview {
    let vm = PullRequestsViewModel(repository: MockGitRepository())
    return PullRequestsView()
        .environment(vm)
        .frame(width: 1000, height: 620)
        .padding()
        .background(Theme.background)
        .task { await vm.refresh() }
}
