// Views/History/CommitChangesetView.swift
// Grove

import SwiftUI

/// Shows the file changeset for a selected commit.
///
/// Clicking a file reveals an inline diff below it (placeholder diff renderer
/// until WS3's DiffView component is available).
struct CommitChangesetView: View {

    @Environment(HistoryViewModel.self) private var viewModel

    var body: some View {
        if viewModel.isLoadingDiff {
            VStack {
                Spacer()
                ProgressView("Loading changeset…")
                    .controlSize(.regular)
                Spacer()
            }
        } else if viewModel.commitDiffs.isEmpty {
            VStack {
                Spacer()
                Text("No changes")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Stats summary
                HStack {
                    Text("\(viewModel.commitDiffs.count) file\(viewModel.commitDiffs.count == 1 ? "" : "s") changed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("+\(totalAdditions) −\(totalDeletions)")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                Divider()

                // File list
                List(selection: selectionBinding) {
                    ForEach(viewModel.commitDiffs, id: \.path) { fileDiff in
                        VStack(alignment: .leading, spacing: 0) {
                            ChangesetFileRow(
                                fileDiff: fileDiff,
                                isSelected: viewModel.selectedFileDiff?.path == fileDiff.path
                            )
                            .tag(fileDiff.path)

                            // Inline diff expansion
                            if viewModel.selectedFileDiff?.path == fileDiff.path,
                               let diff = fileDiff.diff {
                                InlineCommitDiffView(diff: diff)
                                    .transition(.opacity)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: viewModel.selectedFileDiff?.path)
            }
        }
    }

    // MARK: - Helpers

    private var totalAdditions: Int {
        viewModel.commitDiffs.reduce(0) { $0 + $1.stats.additions }
    }

    private var totalDeletions: Int {
        viewModel.commitDiffs.reduce(0) { $0 + $1.stats.deletions }
    }

    private var selectionBinding: Binding<String?> {
        Binding {
            viewModel.selectedFileDiff?.path
        } set: { path in
            if let path {
                viewModel.selectFileDiff(viewModel.commitDiffs.first { $0.path == path })
            } else {
                viewModel.selectFileDiff(nil)
            }
        }
    }
}

// MARK: - InlineCommitDiffView

/// A minimal inline diff renderer for commit changesets.
///
/// A full-featured diff viewer is provided by WS3's DiffView component.
/// This placeholder keeps the History view functional independently.
struct InlineCommitDiffView: View {

    let diff: DiffResult

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(diff.hunks) { hunk in
                // Hunk header
                Text(hunk.header)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.1))

                // Lines
                ForEach(hunk.lines) { line in
                    HStack(spacing: 0) {
                        Text(line.type.prefix)
                            .frame(width: 14, alignment: .leading)
                        Text(line.content)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(lineColor(for: line.type))
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(lineBackground(for: line.type))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.2))
        )
        .padding(.vertical, 4)
    }

    private func lineColor(for type: DiffLineType) -> Color {
        switch type {
        case .addition: return .green
        case .deletion: return .red
        case .context: return .secondary
        }
    }

    private func lineBackground(for type: DiffLineType) -> Color {
        switch type {
        case .addition: return Color.green.opacity(0.08)
        case .deletion: return Color.red.opacity(0.08)
        case .context: return Color.clear
        }
    }
}

private extension DiffLineType {
    var prefix: String {
        switch self {
        case .addition: return "+"
        case .deletion: return "-"
        case .context: return " "
        }
    }
}

#Preview {
    let vm = HistoryViewModel(repository: MockGitRepository())
    vm.commitDiffs = MockData.commitFileDiffs

    return CommitChangesetView()
        .environment(vm)
        .frame(width: 400, height: 400)
}
