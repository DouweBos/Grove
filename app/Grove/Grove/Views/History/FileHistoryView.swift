// Views/History/FileHistoryView.swift
// Grove

import AppKit
import SwiftUI

/// Commits that touched one file (left card) and the file's diff at the selected commit (right card).
struct FileHistoryView: View {
    @Environment(FileHistoryViewModel.self) private var viewModel

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            commitList
                .frame(width: 320)
                .panel()
            diffPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .panel()
        }
        .task { await viewModel.loadHistory() }
    }

    // MARK: - Commits

    private var commitList: some View {
        VStack(spacing: 0) {
            PanelHeader(title: (viewModel.filePath as NSString).lastPathComponent,
                        detail: "\(viewModel.commits.count) commit\(viewModel.commits.count == 1 ? "" : "s")")
            if viewModel.isLoading && viewModel.commits.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.commits.isEmpty {
                EmptyStateView(systemImage: "clock", title: "No History",
                               subtitle: "No commits touch this file.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.commits) { commit in
                            row(commit)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
        }
    }

    private func row(_ commit: CommitInfo) -> some View {
        let isSelected = viewModel.selectedCommit?.id == commit.id
        return HStack(spacing: Theme.Spacing.sm) {
            AvatarView(name: commit.authorName, email: commit.authorEmail, size: .small)
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary).font(.rowTitle).lineLimit(1)
                Text("\(commit.shortSHA) · \(commit.authorName) · \(commit.authorDate.commitRelative())")
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: 44)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.selectionFill)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await viewModel.selectCommit(commit) } }
        .contextMenu {
            Button("Copy Commit SHA") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(commit.id, forType: .string)
            }
            Button("Open Blame at This Revision") { openBlame(commit) }
            Button("Export File at This Revision\u{2026}") { Task { await export(commit) } }
        }
    }

    // MARK: - Diff

    @ViewBuilder
    private var diffPanel: some View {
        if let commit = viewModel.selectedCommit {
            VStack(spacing: 0) {
                PanelHeader(title: commit.summary, detail: commit.shortSHA) {
                    if let diff = viewModel.fileDiff { DiffStatsLabel(stats: diff.stats) }
                    if !isImage { WrapLinesToggle() }
                    Button { openBlame(commit) } label: { Image(systemName: "person.text.rectangle") }
                        .buttonStyle(.borderless)
                        .help("Open Blame at This Revision")
                    Button { Task { await export(commit) } } label: { Image(systemName: "square.and.arrow.down") }
                        .buttonStyle(.borderless)
                        .help("Export File at This Revision\u{2026}")
                }
                if isImage {
                    RepositoryImageDiffView(source: .commit(commit.id, in: viewModel.repository),
                                            path: viewModel.filePath, oldPath: viewModel.fileDiff?.oldPath)
                } else if viewModel.isLoadingDiff {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let diff = viewModel.fileDiff {
                    DiffScrollView { DiffView(diff: diff) }
                        .id(commit.id)
                } else {
                    EmptyStateView(systemImage: "doc.text", title: "No Diff",
                                   subtitle: "This commit has no textual changes for the file.")
                }
            }
        } else {
            EmptyStateView(systemImage: "clock.arrow.circlepath", title: "No Commit Selected",
                           subtitle: "Pick a commit to see how the file changed.")
        }
    }

    private var isImage: Bool { ImageDiffView.supports(path: viewModel.filePath) }

    // MARK: - Actions

    private func openBlame(_ commit: CommitInfo) {
        NotificationCenter.default.post(name: .fileHistoryOpenBlame, object: nil,
                                        userInfo: ["filePath": viewModel.filePath, "revision": commit.id])
    }

    private func export(_ commit: CommitInfo) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (viewModel.filePath as NSString).lastPathComponent
        panel.message = "Export file at revision \(commit.shortSHA)"
        panel.prompt = "Export"
        guard await panel.begin() == .OK, let url = panel.url else { return }
        await viewModel.exportFile(to: url)
    }
}

extension Notification.Name {
    /// userInfo: `"filePath"` (repository-relative) and `"revision"` (full SHA).
    static let fileHistoryOpenBlame = Notification.Name("com.grove.fileHistoryOpenBlame")
}

#Preview {
    let vm = FileHistoryViewModel(repository: MockGitRepository(), filePath: "Grove/Views/History/HistoryView.swift")
    return FileHistoryView()
        .environment(vm)
        .frame(width: 900, height: 520)
        .padding()
        .background(Theme.background)
}
