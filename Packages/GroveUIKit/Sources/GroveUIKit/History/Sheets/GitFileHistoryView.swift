// History/Sheets/GitFileHistoryView.swift
// GroveUIKit
//
// The commits that touched one file beside the file's diff at the selected one; blame, export or restore any version.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

/// File History as a sheet: its bar with Done over the view.
struct FileHistorySheet: View {
    @State private var viewModel: FileHistoryViewModel
    private let history: HistoryViewModel

    init(history: HistoryViewModel, path: String) {
        self.history = history
        _viewModel = State(initialValue: history.fileHistory(path: path))
    }

    var body: some View {
        HistoryToolSheet(title: "File History", detail: viewModel.filePath, done: { history.dismissAction() }) {
            GitFileHistoryView(viewModel: viewModel)
        }
    }
}

public struct GitFileHistoryView: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.gitFeatures) private var features
    @Environment(\.gitHost) private var uiHost
    private let viewModel: FileHistoryViewModel
    private let diffOptions = HistoryDiffOptions()

    /// Blame shows only when the view model has `onOpenBlame`; export needs the `export` feature.
    public init(viewModel: FileHistoryViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        HStack(spacing: GitMetrics.Spacing.md) {
            commitList
                .frame(width: 320 * style.fontScale)
                .gitPanel()
            diffPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gitPanel()
        }
        .task { await viewModel.loadHistory() }
        .confirmationDialog("Restore this version?", isPresented: restoreBinding, titleVisibility: .visible,
                            presenting: viewModel.pendingRestore) { commit in
            Button("Restore", role: .destructive) { Task { await viewModel.restore(commit) } }
            Button("Cancel", role: .cancel) { viewModel.cancelRestore() }
        } message: { commit in
            Text("\(fileName) has local changes. Restoring \(commit.shortSHA) overwrites them in the working copy.")
        }
    }

    private var fileName: String { (viewModel.filePath as NSString).lastPathComponent }

    private var restoreBinding: Binding<Bool> {
        Binding(get: { viewModel.pendingRestore != nil }, set: { if !$0 { viewModel.cancelRestore() } })
    }

    // MARK: Commits

    private var commitList: some View {
        VStack(spacing: 0) {
            GitPanelHeader(title: fileName, detail: "\(viewModel.commits.count) commit\(viewModel.commits.count == 1 ? "" : "s")")
            if viewModel.isLoading && viewModel.commits.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.commits.isEmpty {
                GitEmptyState(systemImage: "clock", title: "No History", subtitle: "No commits touch this file.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.commits) { row($0) }
                    }
                    .padding(.vertical, GitMetrics.Spacing.xs)
                }
            }
        }
    }

    private func row(_ commit: CommitInfo) -> some View {
        let isSelected = viewModel.selectedCommit?.id == commit.id
        return HStack(spacing: GitMetrics.Spacing.sm) {
            CommitAvatar(name: commit.authorName, email: commit.authorEmail, size: .small)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary).font(style.font(13, .medium)).foregroundStyle(style.textPrimary).lineLimit(1)
                Text("\(commit.shortSHA) · \(commit.authorName) · \(commit.authorDate.commitRelative())")
                    .font(style.monoCaption)
                    .foregroundStyle(style.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GitMetrics.Spacing.md)
        .frame(height: 44 * style.fontScale)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: GitMetrics.Radius.row, style: .continuous)
                    .fill(style.selectionFill)
                    .padding(.horizontal, GitMetrics.Spacing.xs)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await viewModel.selectCommit(commit) } }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .contextMenu {
            Button("Copy Commit SHA") {
                uiHost.copy(commit.id)
                uiHost.toast("Copied SHA")
            }
            if viewModel.onOpenBlame != nil {
                Button("Open Blame at This Revision") { Task { await viewModel.openBlame(commit) } }
            }
            Button("Export File at This Revision") { Task { await export(commit) } }
                .requires(.export)
            Divider()
            Button("Restore This Version") { Task { await viewModel.requestRestore(commit) } }
                .disabled(viewModel.isRestoring)
        }
    }

    // MARK: Diff

    @ViewBuilder
    private var diffPanel: some View {
        if let commit = viewModel.selectedCommit {
            VStack(spacing: 0) {
                GitPanelHeader(title: commit.summary, detail: commit.shortSHA) {
                    if let diff = viewModel.fileDiff { DiffStatsLabel(stats: diff.stats) }
                    if !isImage { HistoryDiffToggles(options: diffOptions.options) }
                    if viewModel.onOpenBlame != nil {
                        iconButton("person.text.rectangle", "Open Blame at This Revision") { await viewModel.openBlame(commit) }
                    }
                    iconButton("square.and.arrow.down", "Export File at This Revision") { await export(commit) }
                        .requires(.export)
                    iconButton("clock.arrow.circlepath", "Restore This Version") { await viewModel.requestRestore(commit) }
                        .disabled(!viewModel.canRestoreSelected)
                }
                notices
                if isImage {
                    GitImageDiffView(.commit(commit.id, in: viewModel.repository), path: viewModel.filePath,
                                     oldPath: viewModel.fileDiff?.oldPath, mode: diffOptions.options.imageMode)
                } else if viewModel.isLoadingDiff {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let diff = viewModel.fileDiff {
                    GitDiffView(diff: diff, options: diffOptions.options).id(commit.id)
                } else {
                    GitEmptyState(systemImage: "doc.text", title: "No Diff", subtitle: "This commit has no textual changes for the file.")
                }
            }
        } else {
            GitEmptyState(systemImage: "clock.arrow.circlepath", title: "No Commit Selected",
                          subtitle: "Pick a commit to see how the file changed.")
        }
    }

    private func iconButton(_ symbol: String, _ help: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: { Image(systemName: symbol).font(style.font(13)) }
            .buttonStyle(.borderless)
            .gitClickable()
            .help(help)
            .accessibilityLabel(help)
    }

    private var isImage: Bool { GitImageDiffView.supports(path: viewModel.filePath) }

    @ViewBuilder
    private var notices: some View {
        if let error = viewModel.errorMessage {
            GitBanner(symbol: "xmark.octagon", message: error, tone: .negative, onDismiss: { viewModel.dismissError() })
                .padding(GitMetrics.Spacing.sm)
        } else if let restored = viewModel.restoredCommit {
            GitBanner(symbol: "clock.arrow.circlepath",
                      message: "Restored the version from \(restored.shortSHA) into the working copy. Review it in Changes.",
                      tone: .positive, onDismiss: { viewModel.dismissRestoreNotice() })
                .padding(GitMetrics.Spacing.sm)
        }
    }

    private func export(_ commit: CommitInfo) async {
        guard features.contains(.export),
              let url = await CommitActions.chooseDestination(name: "\(commit.shortSHA)-\(fileName)",
                                                              message: "Export file at revision \(commit.shortSHA)",
                                                              prompt: "Export") else { return }
        await viewModel.exportFile(to: url)
    }
}
#endif
