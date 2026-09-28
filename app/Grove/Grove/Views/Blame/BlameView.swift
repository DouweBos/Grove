// Views/Blame/BlameView.swift
// Grove

import SwiftUI

/// Tracked files on the left; the chosen file annotated line by line on the right.
struct BlameView: View {

    let viewModel: BlameViewModel

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            BlameFileListPanel(viewModel: viewModel)
                .frame(width: 300)
            BlameFilePanel(viewModel: viewModel)
        }
        .padding(.bottom, Theme.Spacing.md)
        .task { await viewModel.loadFilesIfNeeded() }
    }
}

// MARK: - File List

private struct BlameFileListPanel: View {
    let viewModel: BlameViewModel

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Files", detail: "\(viewModel.filteredFiles.count)") {
                Button { Task { await viewModel.reloadFiles() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Reload File List")
            }
            PanelSearchField(placeholder: "Filter files", text: viewModel.filterText, onChange: viewModel.setFilter)
                .padding([.horizontal, .top], Theme.Spacing.sm)
            if viewModel.isLoadingFiles && viewModel.trackedFiles.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredFiles.isEmpty {
                EmptyStateView(systemImage: "doc.text.magnifyingglass", title: "No Matching Files",
                               subtitle: viewModel.trackedFiles.isEmpty ? "This repository has no tracked files." : nil)
            } else {
                SelectableList(items: viewModel.filteredFiles.map(BlameFileItem.init), selection: viewModel.selectedFile,
                               onSelect: { item in Task { await viewModel.open(file: item.id) } }) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        Text((item.id as NSString).lastPathComponent)
                            .font(.rowTitle)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        let directory = (item.id as NSString).deletingLastPathComponent
                        Text(directory.isEmpty ? "/" : directory)
                            .font(.monoCaption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .panel()
    }
}

private struct BlameFileItem: Identifiable {
    let id: String
}

// MARK: - File Panel

private struct BlameFilePanel: View {
    let viewModel: BlameViewModel

    var body: some View {
        Group {
            if let file = viewModel.selectedFile {
                VStack(spacing: 0) {
                    PanelHeader(title: (file as NSString).lastPathComponent, detail: revisionLabel) {
                        navigation
                    }
                    content
                }
            } else {
                EmptyStateView(systemImage: "text.line.first.and.arrowtriangle.forward", title: "Blame a File",
                               subtitle: "Pick a file to see who last changed each line, and in which commit.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panel()
    }

    private var revisionLabel: String {
        let where_ = viewModel.revision.map { "at \($0)" } ?? "working tree"
        return "\(where_) \u{00B7} \(viewModel.lines.count) lines \u{00B7} \(viewModel.commitCount) commits"
    }

    private var navigation: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button { Task { await viewModel.goToPreviousRevision() } } label: { Image(systemName: "chevron.left") }
                .help("Blame Before the Newest Change")
                .disabled(viewModel.lines.isEmpty)
            Button { Task { await viewModel.goForward() } } label: { Image(systemName: "chevron.right") }
                .help("Newer Revision")
                .disabled(!viewModel.canGoForward)
            Button("Latest") { Task { await viewModel.goToWorkingTree() } }
                .disabled(viewModel.isAtWorkingTree)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoadingBlame && viewModel.lines.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = viewModel.errorMessage {
            VStack {
                Banner(symbol: "exclamationmark.triangle", message: error, tone: .negative,
                       actionTitle: viewModel.isAtWorkingTree ? "Retry" : "Latest") {
                    Task { viewModel.isAtWorkingTree ? await viewModel.reload() : await viewModel.goToWorkingTree() }
                }
                Spacer()
            }
            .padding(Theme.Spacing.lg)
        } else {
            GeometryReader { geometry in
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.lines) { line in
                            BlameLineRow(line: line) { sha in Task { await viewModel.blameBefore(sha) } }
                        }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                    // Pin short or narrow files to the top-left instead of centering them.
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                }
            }
            .opacity(viewModel.isLoadingBlame ? 0.5 : 1)
        }
    }
}

// MARK: - Line Row

private struct BlameLineRow: View {
    let line: BlameLine
    let onBlameBefore: (String) -> Void

    private static let annotationWidth: CGFloat = 280
    private static let uncommittedSHA = String(repeating: "0", count: 40)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            annotation
                .frame(width: Self.annotationWidth, alignment: .leading)
            Rectangle()
                .fill(laneColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
            Text("\(line.number)")
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 48, alignment: .trailing)
                .padding(.trailing, Theme.Spacing.md)
            Text(verbatim: line.text.isEmpty ? " " : line.text)
                .font(.monoBody)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize()
                .textSelection(.enabled)
        }
        .frame(minHeight: 18)
        .padding(.trailing, Theme.Spacing.lg)
        .overlay(alignment: .top) {
            if line.startsBlock && line.number > 1 {
                Rectangle().fill(Theme.border).frame(height: 0.5)
            }
        }
    }

    @ViewBuilder
    private var annotation: some View {
        if line.startsBlock, let entry = line.entry {
            let uncommitted = entry.commitSHA == Self.uncommittedSHA
            HStack(spacing: Theme.Spacing.sm) {
                Text(uncommitted ? "Uncommitted" : String(entry.commitSHA.prefix(7)))
                    .font(.monoCaption)
                    .foregroundStyle(uncommitted ? Theme.warning : Theme.accent)
                Text(uncommitted ? "Local changes" : entry.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !uncommitted {
                    Text(entry.authorDate, format: .dateTime.year().month(.abbreviated).day())
                        .font(.monoCaption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .help(uncommitted ? "Not committed yet" : "\(entry.authorName) \u{00B7} \(entry.summary)")
            .contextMenu {
                if !uncommitted {
                    Button("Blame Before This Commit", systemImage: "clock.arrow.circlepath") { onBlameBefore(entry.commitSHA) }
                    Button("Copy SHA", systemImage: "doc.on.doc") { GroveClipboard.copy(entry.commitSHA) }
                }
            }
        } else {
            Color.clear
        }
    }

    private var laneColor: Color {
        guard let sha = line.entry?.commitSHA, sha != Self.uncommittedSHA else { return Theme.subtleFill }
        let seed = sha.prefix(6).unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return Theme.laneColor(seed).opacity(0.7)
    }
}

#Preview {
    let vm = BlameViewModel(repository: MockGitRepository())
    return BlameView(viewModel: vm)
        .frame(width: 1100, height: 600)
        .padding()
        .background(Theme.background)
        .task { await vm.open(file: "Sources/App.swift") }
}
