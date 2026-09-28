// Views/PullRequests/PullRequestDetailView.swift
// Grove

import SwiftUI

/// Detail card for the selected pull request: header, actions, and Overview / Commits / Files tabs.
struct PullRequestDetailView: View {

    @Environment(PullRequestsViewModel.self) private var viewModel

    var body: some View {
        Group {
            if let pr = viewModel.selectedPR {
                VStack(spacing: 0) {
                    header(pr)
                    Rectangle().fill(Theme.border).frame(height: 0.5)
                    tabContent(pr)
                }
            } else {
                EmptyStateView(systemImage: "arrow.triangle.pull", title: "No Pull Request Selected",
                               subtitle: "Select a pull request to read its description, commits and changes.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panel()
    }

    // MARK: - Header

    private func header(_ pr: PullRequestInfo) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(pr.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .textSelection(.enabled)
                    HStack(spacing: Theme.Spacing.sm) {
                        stateBadge(pr)
                        Text("#\(String(pr.id)) \u{00B7} \(pr.authorName) \u{00B7} opened \(pr.createdDate.formatted(.relative(presentation: .named)))")
                            .font(.monoCaption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    HStack(spacing: Theme.Spacing.xs) {
                        BranchLabel(name: pr.sourceBranch, kind: .localBranch(isHEAD: false))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                        BranchLabel(name: pr.targetBranch, kind: .remoteBranch)
                    }
                }
                Spacer(minLength: Theme.Spacing.md)
                if viewModel.isRevalidating {
                    ProgressView().controlSize(.small).help("Checking GitHub for changes")
                }
                actions(pr)
            }
            Picker("Section", selection: Binding(get: { viewModel.activeDetailTab },
                                                 set: { tab in Task { await viewModel.selectTab(tab) } })) {
                ForEach(PRDetailTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
        }
        .padding(Theme.Spacing.lg)
    }

    private func stateBadge(_ pr: PullRequestInfo) -> some View {
        let tone: StatusBadge.Tone = switch pr.state {
        case .open: pr.isDraft ? .neutral : .positive
        case .merged: .neutral
        case .closed: .negative
        }
        let title = pr.isDraft && pr.state == .open ? "Draft" : pr.state.rawValue.capitalized
        return StatusBadge(title: title, symbol: pr.stateSymbol, tone: tone)
    }

    private func actions(_ pr: PullRequestInfo) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button { viewModel.openInBrowser(pr) } label: { Image(systemName: "safari") }
                .help("Open on GitHub")
            Button("Check Out") { Task { await viewModel.checkout(pr) } }
            if pr.state == .open {
                Menu("More") {
                    Button("Merge on GitHub\u{2026}") { viewModel.request(.merge, on: pr) }
                        .disabled(pr.isDraft)
                    Button("Close Pull Request\u{2026}", role: .destructive) { viewModel.request(.close, on: pr) }
                }
                .fixedSize()
            }
        }
        .disabled(viewModel.isPerforming)
    }

    // MARK: - Tabs

    @ViewBuilder
    private func tabContent(_ pr: PullRequestInfo) -> some View {
        switch viewModel.activeDetailTab {
        case .overview:
            ScrollView { overview(pr).padding(Theme.Spacing.lg).frame(maxWidth: .infinity, alignment: .leading) }
        case .commits:
            commits
        case .files:
            ChangesetBrowser(files: viewModel.prChangeset, selectedPath: viewModel.selectedChangesetPath,
                             isLoading: viewModel.isLoadingChangeset, emptyTitle: "No File Changes") {
                viewModel.selectChangesetFile($0)
            }
        }
    }

    private func overview(_ pr: PullRequestInfo) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionLabel(title: "Description")
                if let body = pr.body, !body.isEmpty {
                    MarkdownRenderer(markdown: body, fontSize: 13)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                } else {
                    Text("No description provided.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
            }
            HStack(alignment: .top, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    SectionLabel(title: "Checks")
                    Label(checksText(pr.checksStatus), systemImage: pr.checksStatus.symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(pr.checksStatus.color)
                }
                if !pr.reviewers.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SectionLabel(title: "Review Requested")
                        Text(pr.reviewers.joined(separator: ", ")).font(.system(size: 13))
                    }
                }
                if !pr.labels.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        SectionLabel(title: "Labels")
                        HStack(spacing: Theme.Spacing.xs) {
                            ForEach(pr.labels) { StatusBadge(title: $0.name, symbol: "tag", tone: .neutral) }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionLabel(title: "Conversation", count: viewModel.comments.count)
                if viewModel.isLoadingComments {
                    ProgressView().controlSize(.small)
                } else if viewModel.comments.isEmpty {
                    Text("No comments yet.").font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                } else {
                    ForEach(viewModel.comments) { PRCommentView(comment: $0) }
                }
            }
        }
    }

    private func checksText(_ status: PRChecksStatus) -> String {
        switch status {
        case .passing: "All checks passed"
        case .failing: "Some checks failed"
        case .pending: "Checks in progress"
        case .none: "No checks reported"
        }
    }

    @ViewBuilder
    private var commits: some View {
        if viewModel.isLoadingPRCommits {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.prCommits.isEmpty {
            EmptyStateView(systemImage: "clock", title: "No Commits")
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(viewModel.prCommits) { commit in
                        HStack(spacing: Theme.Spacing.md) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(commit.summary).font(.rowTitle).foregroundStyle(Theme.textPrimary).lineLimit(1)
                                Text("\(commit.authorName) \u{00B7} \(commit.authorDate.formatted(.relative(presentation: .named)))")
                                    .font(.monoCaption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Text(commit.shortSHA).font(.monoCaption).foregroundStyle(Theme.accent)
                        }
                        .selectableRow(isSelected: false)
                        .contextMenu {
                            Button("Copy SHA", systemImage: "doc.on.doc") { GroveClipboard.copy(commit.id) }
                        }
                    }
                }
                .padding(Theme.Spacing.sm)
            }
        }
    }
}

#Preview {
    let vm = PullRequestsViewModel(repository: MockGitRepository())
    return PullRequestDetailView()
        .environment(vm)
        .frame(width: 620, height: 640)
        .padding()
        .background(Theme.background)
        .task {
            await vm.refresh()
            if let first = vm.pullRequests.first { await vm.select(first) }
        }
}
