// Views/History/FileHistoryView.swift
// Grove

import AppKit
import SwiftUI

// MARK: - FileHistoryView

/// A two-panel view showing the commit history for a single file.
///
/// Left panel: list of commits that touched the file (following renames).
/// Right panel: the file diff at the selected commit revision.
///
/// Opened from the commit changeset or blame views when the user wants to
/// explore how a specific file evolved over time.
struct FileHistoryView: View {

    @Environment(FileHistoryViewModel.self) private var viewModel

    var body: some View {
        HSplitView {
            // MARK: Left — commit list
            fileCommitList
                .frame(minWidth: 260, maxWidth: 420)

            // MARK: Right — diff panel
            fileDiffPanel
                .frame(minWidth: 300)
                .background(Theme.surface)
        }
        .task {
            await viewModel.loadHistory()
        }
    }

    // MARK: - Left Panel

    private var fileCommitList: some View {
        VStack(spacing: 0) {
            // Header bar showing the file path
            filePathHeader

            Divider()

            if viewModel.isLoading {
                Spacer()
                ProgressView("Loading history\u{2026}")
                    .padding()
                Spacer()
            } else if viewModel.commits.isEmpty {
                Spacer()
                Text("No history found")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                commitList
            }
        }
    }

    private var filePathHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .imageScale(.small)
                .foregroundStyle(.secondary)
            Text(viewModel.filePath)
                .font(.subheadline)
                .fontDesign(.monospaced)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(viewModel.commits.count) commits")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var commitList: some View {
        List(selection: selectedCommitBinding) {
            ForEach(viewModel.commits) { commit in
                fileCommitRow(commit)
                    .tag(commit)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - File Commit Row

    private func fileCommitRow(_ commit: CommitInfo) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(commit.summary)
                .font(.subheadline)
                .lineLimit(2)
                .truncationMode(.tail)

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
                Spacer()
                Text(commit.shortSHA)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            fileCommitContextMenu(commit)
        }
    }

    @ViewBuilder
    private func fileCommitContextMenu(_ commit: CommitInfo) -> some View {
        Button("Copy Commit SHA") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.id, forType: .string)
        }
        Divider()
        Button("Open Blame at This Revision") {
            // Blame navigation is handled by the parent window coordinator;
            // here we simply post a notification with the commit SHA.
            NotificationCenter.default.post(
                name: .fileHistoryOpenBlame,
                object: nil,
                userInfo: [
                    "filePath": viewModel.filePath,
                    "revision": commit.id
                ]
            )
        }
        Button("Export File at This Revision\u{2026}") {
            Task { await exportFileAtRevision(commit) }
        }
    }

    // MARK: - Right Panel

    private var fileDiffPanel: some View {
        VStack(spacing: 0) {
            if let commit = viewModel.selectedCommit {
                diffPanelHeader(commit)
                Divider()
            }

            if viewModel.isLoadingDiff {
                Spacer()
                ProgressView("Loading diff\u{2026}")
                    .padding()
                Spacer()
            } else if let diff = viewModel.fileDiff {
                diffContent(diff)
            } else if viewModel.selectedCommit != nil {
                noDiffState
            } else {
                emptySelectionState
            }
        }
    }

    private func diffPanelHeader(_ commit: CommitInfo) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(commit.summary)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(commit.authorName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\u{B7}")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(commit.authorDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 6) {
                Button {
                    NotificationCenter.default.post(
                        name: .fileHistoryOpenBlame,
                        object: nil,
                        userInfo: [
                            "filePath": viewModel.filePath,
                            "revision": commit.id
                        ]
                    )
                } label: {
                    Label("Blame", systemImage: "person.line.dotted.person.fill")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Open Blame at This Revision")

                Button {
                    Task { await exportFileAtRevision(commit) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Export File at This Revision\u{2026}")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func diffContent(_ diff: DiffResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Stats summary bar
                HStack {
                    Text(diff.filePath)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text("+\(diff.stats.additions) \u{2212}\(diff.stats.deletions)")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                InlineCommitDiffView(diff: diff)
                    .padding(8)
            }
        }
    }

    private var noDiffState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No diff available")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySelectionState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Select a commit to view the diff")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var selectedCommitBinding: Binding<CommitInfo?> {
        Binding {
            viewModel.selectedCommit
        } set: { commit in
            if let commit {
                Task { await viewModel.selectCommit(commit) }
            }
        }
    }

    private func exportFileAtRevision(_ commit: CommitInfo) async {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (viewModel.filePath as NSString).lastPathComponent
        panel.message = "Export file at revision \(commit.shortSHA)"
        panel.prompt = "Export"

        let response = await panel.beginSheetModal(for: NSApp.keyWindow ?? NSWindow())
        guard response == .OK, let url = panel.url else { return }
        await viewModel.exportFile(to: url)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the user requests to open the blame view at a specific file revision.
    ///
    /// `userInfo` keys:
    /// - `"filePath"`: `String` — repository-relative path.
    /// - `"revision"`: `String` — the full commit SHA.
    static let fileHistoryOpenBlame = Notification.Name("com.grove.fileHistoryOpenBlame")
}

// MARK: - Preview

#Preview {
    let repo = MockGitRepository()
    let vm = FileHistoryViewModel(
        repository: repo,
        filePath: "Sources/Grove/Views/History/HistoryView.swift"
    )
    return FileHistoryView()
        .environment(vm)
        .frame(width: 820, height: 520)
        .task { await vm.loadHistory() }
}
