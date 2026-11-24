// Reflog/ReflogDetailPanel.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// The selected entry: what happened, the commit it points at with its changes, and restore actions.
struct ReflogDetailPanel: View {
    @Environment(\.gitStyle) private var style
    let viewModel: ReflogViewModel
    let actions: ReflogActions
    let options: GitDiffOptions?
    @State private var diffs: [FileDiff] = []
    @State private var expanded: Set<String> = []
    @State private var layout = GitDiffLayout.inline
    @State private var wraps = false
    @State private var imageMode = GitImageDiffMode.sideBySide

    private var diffOptions: GitDiffOptions {
        options ?? GitDiffOptions(layout: $layout, wrapsLines: $wraps, imageMode: $imageMode)
    }

    var body: some View {
        Group {
            if let entry = viewModel.selectedEntry {
                VStack(spacing: 0) {
                    header(entry)
                    Rectangle().fill(style.border).frame(height: 0.5)
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            commitSection(entry)
                                .padding(GitMetrics.Spacing.lg)
                            if !diffs.isEmpty {
                                GitSectionLabel(title: "Changed Files", count: diffs.count) { HistoryDiffToggles(options: diffOptions) }
                                    .padding(.horizontal, GitMetrics.Spacing.lg)
                                    .padding(.bottom, GitMetrics.Spacing.xs)
                                ChangesetFiles(files: diffs, expanded: expanded, toggle: toggle, options: diffOptions,
                                               images: .commit(entry.newSHA, in: viewModel.repository)) { _ in AnyView(EmptyView()) }
                            }
                        }
                    }
                }
                .task(id: entry.newSHA) {
                    expanded = []
                    // A commit gone after gc has no diff; the entry still shows.
                    diffs = (try? await viewModel.repository.diffForCommit(entry.newSHA)) ?? []
                }
            } else {
                GitEmptyState(systemImage: "clock.arrow.circlepath", title: "No Entry Selected",
                              subtitle: "Select a reflog entry to inspect it or restore HEAD to that point.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gitPanel()
    }

    private func toggle(_ path: String) {
        if expanded.contains(path) { expanded.remove(path) } else { expanded.insert(path) }
    }

    private func header(_ entry: ReflogEntry) -> some View {
        let action = viewModel.actionType(for: entry)
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: GitMetrics.Spacing.md) {
                summary(entry, action: action)
                Spacer(minLength: GitMetrics.Spacing.md)
                buttons(entry)
            }
            VStack(alignment: .leading, spacing: GitMetrics.Spacing.sm) {
                summary(entry, action: action)
                buttons(entry)
            }
        }
        .padding(GitMetrics.Spacing.lg)
    }

    private func summary(_ entry: ReflogEntry, action: ReflogActionType) -> some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.xs) {
            HStack(spacing: GitMetrics.Spacing.sm) {
                Text("HEAD@{\(viewModel.index(of: entry))}")
                    .font(style.font(17, .semibold, .monospaced))
                    .foregroundStyle(style.textPrimary)
                Label(action.displayName, systemImage: action.systemImage)
                    .font(style.font(11, .semibold))
                    .foregroundStyle(action.color(style))
                    .padding(.horizontal, GitMetrics.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(action.color(style).opacity(0.14), in: Capsule())
                    .fixedSize()
            }
            Text(entry.message)
                .font(style.font(13))
                .foregroundStyle(style.textSecondary)
                .textSelection(.enabled)
                .lineLimit(2)
            HStack(spacing: GitMetrics.Spacing.md) {
                Text("\(entry.oldSHA.prefix(7)) \u{2192} \(entry.newSHA.prefix(7))")
                Text(entry.date.formatted(date: .abbreviated, time: .shortened)).lineLimit(1)
            }
            .font(style.monoCaption)
            .foregroundStyle(style.textSecondary)
        }
    }

    private func buttons(_ entry: ReflogEntry) -> some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            Button("New Branch") { actions.present(.createBranch(from: entry.newSHA)) }
                .requires(.createBranch)
            Menu("Reset HEAD") {
                Button("Soft, keep index and files") { viewModel.requestReset(to: entry, mode: .soft) }
                Button("Mixed, keep files") { viewModel.requestReset(to: entry, mode: .mixed) }
                Divider()
                Button("Hard, discard all changes", role: .destructive) { viewModel.requestReset(to: entry, mode: .hard) }
            }
            .gitClickable()
        }
        .fixedSize()
    }

    @ViewBuilder
    private func commitSection(_ entry: ReflogEntry) -> some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.sm) {
            GitSectionLabel(title: "Commit")
            if viewModel.isLoadingDetail {
                ProgressView().controlSize(.small)
            } else if let commit = viewModel.selectedCommit {
                commitCard(commit)
            } else {
                GitBanner(symbol: "questionmark.circle", message: "Commit \(entry.newSHA.prefix(7)) is no longer in the object database.")
            }
        }
    }

    private func commitCard(_ commit: CommitInfo) -> some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.md) {
            VStack(alignment: .leading, spacing: GitMetrics.Spacing.xs) {
                Text(commit.summary)
                    .font(style.font(15, .semibold))
                    .foregroundStyle(style.textPrimary)
                    .textSelection(.enabled)
                if let body = commit.body, !body.isEmpty {
                    Text(body).font(style.font(13)).foregroundStyle(style.textSecondary).textSelection(.enabled)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: GitMetrics.Spacing.lg, verticalSpacing: GitMetrics.Spacing.xs) {
                GridRow {
                    Text("Author").foregroundStyle(style.textSecondary)
                    Text("\(commit.authorName) <\(commit.authorEmail)>").textSelection(.enabled)
                }
                GridRow {
                    Text("Date").foregroundStyle(style.textSecondary)
                    Text(commit.authorDate.formatted(date: .long, time: .shortened))
                }
                GridRow {
                    Text("SHA").foregroundStyle(style.textSecondary)
                    HStack(spacing: GitMetrics.Spacing.xs) {
                        Text(commit.id).font(style.monoCaption).textSelection(.enabled).lineLimit(1)
                        HistoryCopyButton(value: { commit.id }, help: "Copy SHA", confirmation: "Copied SHA")
                    }
                }
                if commit.isSigned {
                    GridRow {
                        Text("Signature").foregroundStyle(style.textSecondary)
                        GitStatusBadge(title: "Verified", symbol: "checkmark.seal.fill", tone: .positive)
                    }
                }
            }
            .font(style.font(13))
            .foregroundStyle(style.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(GitMetrics.Spacing.md)
        .background(style.surfaceRaised, in: RoundedRectangle(cornerRadius: GitMetrics.Radius.row, style: .continuous))
    }
}
#endif
