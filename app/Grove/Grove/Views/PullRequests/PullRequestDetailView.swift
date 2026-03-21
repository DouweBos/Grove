// Views/PullRequests/PullRequestDetailView.swift
// Grove

import SwiftUI

/// Detail panel for a selected pull request.
///
/// Shows a tab bar at the top with three tabs:
/// - **Overview** — PR title, author, branch flow, description, labels, checks, and comments.
/// - **Commits** — ordered list of commits on the PR's source branch.
/// - **Files** — combined file changeset across the whole PR.
///
/// The ``PRActionBar`` is pinned at the bottom in all tabs.
struct PullRequestDetailView: View {

    @Environment(PullRequestsViewModel.self) private var viewModel

    var body: some View {
        if let pr = viewModel.selectedPR {
            VStack(spacing: 0) {
                // MARK: Tab bar
                tabBar(pr: pr)

                Divider()

                // MARK: Tab content
                tabContent(pr: pr)

                Divider()

                // MARK: Action bar (always visible)
                PRActionBar(
                    pr: pr,
                    onCheckout: { Task { await viewModel.checkout(pr: pr) } },
                    onClose:    { Task { await viewModel.close(pr: pr) } },
                    onMerge:    { Task { await viewModel.merge(pr: pr) } }
                )
            }
            .alert("Action Failed", isPresented: .constant(viewModel.actionError != nil)) {
                Button("OK") { viewModel.actionError = nil }
            } message: {
                Text(viewModel.actionError ?? "")
            }
        } else {
            emptyState
        }
    }

    // MARK: - Tab Bar

    private func tabBar(pr: PullRequestInfo) -> some View {
        @Bindable var vm = viewModel
        return HStack(spacing: 0) {
            ForEach(PRDetailTab.allCases, id: \.self) { tab in
                tabButton(tab: tab, pr: pr, selectedTab: $vm.activeDetailTab)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .background(.bar)
    }

    private func tabButton(
        tab: PRDetailTab,
        pr: PullRequestInfo,
        selectedTab: Binding<PRDetailTab>
    ) -> some View {
        let isSelected = selectedTab.wrappedValue == tab
        return Button {
            selectedTab.wrappedValue = tab
            // Trigger lazy loads when switching tabs.
            switch tab {
            case .commits:
                Task { await viewModel.loadPRCommits(for: pr) }
            case .files:
                Task { await viewModel.loadChangeset(for: pr) }
            case .overview:
                break
            }
        } label: {
            VStack(spacing: 0) {
                Text(tab.rawValue)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                // Selection indicator
                Rectangle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    // MARK: - Tab Content

    @ViewBuilder
    private func tabContent(pr: PullRequestInfo) -> some View {
        switch viewModel.activeDetailTab {
        case .overview:
            overviewContent(pr: pr)
        case .commits:
            PRCommitsTab()
        case .files:
            PRChangesetTab()
        }
    }

    // MARK: - Overview Content (previously the full body)

    private func overviewContent(pr: PullRequestInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                prHeader(pr)
                Divider()
                branchSection(pr)

                if let body = pr.body, !body.isEmpty {
                    Divider()
                    bodySection(body)
                }

                if !pr.labels.isEmpty {
                    Divider()
                    labelsSection(pr.labels)
                }

                Divider()
                checksSection(pr.checksStatus)

                Divider()
                commentsSection
            }
            .padding(16)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.merge")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Select a pull request to view details")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - PR Header

    @ViewBuilder
    private func prHeader(_ pr: PullRequestInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Number + state pill
            HStack(alignment: .center, spacing: 8) {
                Text("#\(pr.id)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)

                prStatePill(pr.state)

                if pr.isDraft {
                    Text("Draft")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
            }

            // Title
            Text(pr.title)
                .font(.title2)
                .fontWeight(.semibold)
                .textSelection(.enabled)

            // Author row
            HStack(spacing: 8) {
                PRAuthorAvatarView(name: pr.authorName)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(pr.authorName)
                        .fontWeight(.medium)
                        .font(.subheadline)
                    Text("opened \(pr.createdDate, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - State Pill

    @ViewBuilder
    private func prStatePill(_ state: PRState) -> some View {
        let (label, color): (String, Color) = switch state {
        case .open:   ("Open",   .green)
        case .closed: ("Closed", .red)
        case .merged: ("Merged", .purple)
        }

        Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }

    // MARK: - Branch Section

    @ViewBuilder
    private func branchSection(_ pr: PullRequestInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Branches")

            HStack(spacing: 6) {
                Label(pr.sourceBranch, systemImage: "arrow.triangle.branch")
                    .font(.subheadline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))

                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Text(pr.targetBranch)
                    .font(.subheadline)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    // MARK: - Body Section

    @ViewBuilder
    private func bodySection(_ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Description")
            MarkdownRenderer(markdown: body, fontSize: 13)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Labels Section

    @ViewBuilder
    private func labelsSection(_ labels: [PRLabel]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Labels")
            FlowLayout(spacing: 6) {
                ForEach(labels) { label in
                    PRLabelPill(label: label)
                }
            }
        }
    }

    // MARK: - Checks Section

    @ViewBuilder
    private func checksSection(_ status: PRChecksStatus) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Checks")

            HStack(spacing: 8) {
                checksIcon(status)
                Text(checksLabel(status))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func checksIcon(_ status: PRChecksStatus) -> some View {
        switch status {
        case .passing:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failing:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .pending:
            Image(systemName: "clock.circle.fill").foregroundStyle(.yellow)
        case .none:
            Image(systemName: "minus.circle").foregroundStyle(.tertiary)
        }
    }

    private func checksLabel(_ status: PRChecksStatus) -> String {
        switch status {
        case .passing: return "All checks passed"
        case .failing: return "Some checks failed"
        case .pending: return "Checks in progress"
        case .none:    return "No checks configured"
        }
    }

    // MARK: - Comments Section

    @ViewBuilder
    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Comments")

            if viewModel.isLoadingComments {
                HStack {
                    Spacer()
                    ProgressView("Loading comments\u{2026}")
                    Spacer()
                }
                .padding(.vertical, 8)
            } else if viewModel.comments.isEmpty {
                Text("No comments yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(viewModel.comments) { comment in
                    PRCommentView(comment: comment)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

// MARK: - FlowLayout

/// A simple wrapping horizontal layout for label pills.
private struct FlowLayout: Layout {

    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        y += rowHeight
        return CGSize(width: maxWidth, height: y)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

#Preview {
    let vm = PullRequestsViewModel(repository: MockGitRepository())
    vm.selectedPR = MockData.pullRequests[0]
    vm.comments   = MockData.prComments

    return PullRequestDetailView()
        .environment(vm)
        .frame(width: 480, height: 680)
}
