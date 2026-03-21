// Views/PullRequests/PRCommitsTab.swift
// Grove

import SwiftUI

// MARK: - PRCommitsTab

/// The "Commits" tab inside ``PullRequestDetailView``.
///
/// Shows the ordered list of commits on the PR's source branch that would be
/// merged into the target. Each row uses the same compact layout as a commit
/// in the History view — author, date, short SHA — without graph lanes.
///
/// Selecting a commit copies its SHA to the pasteboard via a context menu.
struct PRCommitsTab: View {

    @Environment(PullRequestsViewModel.self) private var viewModel

    var body: some View {
        if viewModel.isLoadingPRCommits {
            loadingState
        } else if viewModel.prCommits.isEmpty {
            emptyState
        } else {
            commitList
        }
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView("Loading commits\u{2026}")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No commits found")
                .foregroundStyle(.secondary)
            Text("Commits on the source branch will appear here.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Commit List

    private var commitList: some View {
        VStack(spacing: 0) {
            // Stats bar
            statsBar

            Divider()

            List(viewModel.prCommits, id: \.id) { commit in
                PRCommitRow(commit: commit)
                    .contextMenu { contextMenu(for: commit) }
            }
            .listStyle(.plain)
        }
    }

    private var statsBar: some View {
        HStack {
            Text("\(viewModel.prCommits.count) commit\(viewModel.prCommits.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if let pr = viewModel.selectedPR {
                Label(pr.sourceBranch, systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(pr.targetBranch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenu(for commit: CommitInfo) -> some View {
        Button("Copy Commit SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.id, forType: .string)
        }
        Button("Copy Short SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.shortSHA, forType: .string)
        }
    }
}

// MARK: - PRCommitRow

/// A single commit row in the PR commits tab.
///
/// Compact layout: avatar initials circle, commit message, author, relative date, short SHA.
private struct PRCommitRow: View {

    let commit: CommitInfo

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            // Small avatar circle
            miniAvatar

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(commit.summary)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    if commit.isMerge {
                        Image(systemName: "arrow.triangle.merge")
                            .imageScale(.small)
                            .foregroundStyle(.secondary)
                    }
                    if commit.isSigned {
                        Image(systemName: "checkmark.seal.fill")
                            .imageScale(.small)
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 4) {
                    Text(commit.authorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\u{B7}")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(commit.authorDate, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(commit.shortSHA)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    // MARK: Helpers

    private var miniAvatar: some View {
        ZStack {
            Circle()
                .fill(avatarColor.gradient)
            Text(initials)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 20, height: 20)
    }

    private var initials: String {
        let parts = commit.authorName.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.dropFirst().first?.prefix(1) ?? ""
        return "\(first)\(last)".uppercased()
    }

    private var avatarColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .teal, .indigo]
        let index = abs(commit.authorEmail.hashValue) % colors.count
        return colors[index]
    }
}

// MARK: - Preview

#Preview {
    let vm = PullRequestsViewModel(repository: MockGitRepository())
    vm.selectedPR = MockData.pullRequests[0]
    vm.prCommits = MockData.commits

    return PRCommitsTab()
        .environment(vm)
        .frame(width: 480, height: 420)
}
