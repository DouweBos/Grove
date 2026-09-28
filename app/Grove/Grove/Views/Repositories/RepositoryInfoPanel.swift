// Views/Repositories/RepositoryInfoPanel.swift
// Grove
//
// Browser detail for the selected bookmark: name, status badges, facts,
// recent commits and remotes, with a prominent Open button.

import AppKit
import SwiftUI

struct RepositoryInfoPanel: View {

    @Environment(WindowViewModel.self) private var viewModel

    let bookmark: RepositoryBookmarkData

    private var snapshot: RepositorySnapshot? { viewModel.snapshot(for: bookmark) }
    private var isRefreshing: Bool { viewModel.isRefreshingSnapshot(for: bookmark) }
    private var loadError: String? { viewModel.snapshotError(for: bookmark) }

    private var exists: Bool { FileManager.default.fileExists(atPath: bookmark.path) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                header
                if !exists, let worktree, let mainRepositoryName {
                    Banner(symbol: "questionmark.folder",
                           message: "This worktree's folder is gone. Pruning removes the stale entry from \(mainRepositoryName).",
                           actionTitle: "Prune Worktrees",
                           action: { Task { await viewModel.pruneWorktrees(ofRepositoryAt: worktree.mainRepositoryPath) } })
                } else if !exists {
                    Banner(symbol: "questionmark.folder", message: "This folder no longer exists. It may have been moved or deleted.",
                           actionTitle: "Remove from List", action: { viewModel.removeBookmark(bookmark) })
                } else if let loadError {
                    Banner(symbol: "exclamationmark.triangle", message: loadError)
                }
                facts
                if let snapshot {
                    RecentCommitsCard(commits: snapshot.commits, branch: snapshot.branch?.name)
                    if !snapshot.remotes.isEmpty { RemotesCard(remotes: snapshot.remotes) }
                } else if isRefreshing {
                    // Only the first read of a repository has nothing to show yet.
                    ProgressStrip(title: "Reading repository…", detail: "")
                }
            }
            .padding(Theme.Spacing.xl)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .task(id: bookmark.id) { await viewModel.refreshSnapshot(for: bookmark) }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(bookmark.displayName)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(abbreviatingHome(bookmark.path))
                        .font(.monoCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .textSelection(.enabled)
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: bookmark.path)])
                    } label: {
                        Image(systemName: "arrow.forward.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .help("Reveal in Finder")
                    if isRefreshing, snapshot != nil {
                        ProgressView()
                            .controlSize(.mini)
                            .help("Refreshing…")
                            .accessibilityLabel("Refreshing")
                    }
                }
                badges
            }
            Spacer(minLength: Theme.Spacing.md)
            Button {
                viewModel.openBookmark(bookmark)
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
                    .padding(.horizontal, Theme.Spacing.sm)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!exists)
            .help("Open repository (Return)")
        }
    }

    private var worktree: LinkedWorktree? { viewModel.linkedWorktree(for: bookmark) }

    private var mainRepositoryName: String? {
        worktree.map { URL(fileURLWithPath: $0.mainRepositoryPath).lastPathComponent }
    }

    @ViewBuilder
    private var badges: some View {
        if let snapshot {
            HStack(spacing: Theme.Spacing.xs) {
                if let worktree, let mainRepositoryName {
                    Button { viewModel.selectRepository(atPath: worktree.mainRepositoryPath) } label: {
                        StatusBadge(title: "Worktree of \(mainRepositoryName)", symbol: "tree", tone: .neutral)
                    }
                    .buttonStyle(.plain)
                    .help("Show \(mainRepositoryName)")
                }
                if let branch = snapshot.branch {
                    BranchLabel(name: branch.name, kind: .localBranch(isHEAD: true))
                } else {
                    StatusBadge(title: "Detached HEAD", symbol: "exclamationmark.triangle.fill", tone: .caution)
                }
                if snapshot.changedCount == 0 {
                    StatusBadge(title: "Clean", symbol: "checkmark.circle.fill", tone: .positive)
                } else {
                    StatusBadge(title: "\(snapshot.changedCount) changed", symbol: "pencil.circle.fill", tone: .caution)
                }
                if let branch = snapshot.branch, branch.ahead > 0 {
                    StatusBadge(title: "\(branch.ahead) to push", symbol: "arrow.up", tone: .neutral)
                }
                if let branch = snapshot.branch, branch.behind > 0 {
                    StatusBadge(title: "\(branch.behind) to pull", symbol: "arrow.down", tone: .caution)
                }
            }
        }
    }

    // MARK: Facts

    private var facts: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xl) {
            fact("Last Opened") {
                if let date = bookmark.displayLastOpenedDate {
                    Text(date, format: .relative(presentation: .named))
                } else {
                    Text("Never")
                }
            }
            if viewModel.isSyntheticWorktreeRow(bookmark) {
                // Discovered from disk rather than added, so there's no added date to show.
                fact("Folder") { Text(URL(fileURLWithPath: bookmark.path).lastPathComponent).lineLimit(1).truncationMode(.middle) }
            } else {
                fact("Added") { Text(bookmark.addedDate, format: .dateTime.day().month().year()) }
            }
            fact("Upstream") { Text(snapshot?.branch?.upstreamShortName ?? "–") }
            if let mainRepositoryName {
                fact("Repository") { Text(mainRepositoryName) }
            } else {
                fact("Group") {
                    Text(viewModel.sortedGroups.first(where: { $0.id == bookmark.groupID })?.name ?? "None")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func fact<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            value()
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

#Preview {
    let manager = MockRepositoryManager()
    let vm = WindowViewModel(manager: manager)
    return RepositoryInfoPanel(bookmark: manager.bookmarks[0])
        .environment(vm)
        .frame(width: 760, height: 600)
}
