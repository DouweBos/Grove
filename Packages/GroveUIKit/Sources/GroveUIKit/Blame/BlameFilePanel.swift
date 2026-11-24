// Blame/BlameFilePanel.swift
// GroveUIKit
//
// The chosen file: its revision and how to step through them over the blamed lines.

#if os(macOS)
import GroveKit
import SwiftUI

struct BlameFilePanel: View {
    @Environment(\.gitStyle) private var style
    let viewModel: BlameViewModel
    let host: GitBlameHost
    /// Back to the picker, when it isn't beside the file.
    let back: (() -> Void)?

    var body: some View {
        Group {
            if let file = viewModel.selectedFile {
                VStack(spacing: 0) {
                    GitPanelHeader(title: (file as NSString).lastPathComponent, detail: detail) { accessories }
                        .help(file)
                    content
                }
            } else {
                GitEmptyState(systemImage: "text.line.first.and.arrowtriangle.forward", title: "Blame a File",
                              subtitle: "Pick a file to see who last changed each line, and in which commit.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gitPanel()
    }

    /// Where in the file's history this is, and how much of it shows.
    var detail: String {
        let lines = viewModel.lines.count
        let commits = viewModel.commitCount
        return "\(Self.revisionLabel(viewModel.revision)) \u{00B7} \(lines.formatted()) line\(lines == 1 ? "" : "s")"
            + " \u{00B7} \(commits) commit\(commits == 1 ? "" : "s")"
    }

    static func revisionLabel(_ revision: String?) -> String {
        guard let revision else { return "working tree" }
        guard revision.hasSuffix("^") else { return "at \(revision.prefix(12))" }
        return "before \(revision.dropLast().prefix(7))"
    }

    private var accessories: some View {
        HStack(spacing: GitMetrics.Spacing.xs) {
            if viewModel.isLoadingBlame && !viewModel.lines.isEmpty { ProgressView().controlSize(.mini) }
            if let back {
                Button(action: back) { Image(systemName: "doc.text.magnifyingglass") }
                    .gitClickable()
                    .help("Choose Another File")
                    .accessibilityLabel("Choose File")
            }
            Button { Task { await viewModel.goToPreviousRevision() } } label: { Image(systemName: "chevron.left") }
                .gitClickable()
                .help("Blame Before the Newest Change")
                .accessibilityLabel("Older")
                .disabled(viewModel.lines.isEmpty)
            Button { Task { await viewModel.goForward() } } label: { Image(systemName: "chevron.right") }
                .gitClickable()
                .help("Newer Revision")
                .accessibilityLabel("Newer")
                .disabled(!viewModel.canGoForward)
            Button("Latest") { Task { await viewModel.goToWorkingTree() } }
                .gitClickable()
                .help("Blame the Working Tree")
                .disabled(viewModel.isAtWorkingTree)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    @ViewBuilder
    private var content: some View {
        if let error = viewModel.errorMessage {
            VStack {
                GitBanner(symbol: "exclamationmark.triangle", message: error, tone: .negative,
                          actionTitle: viewModel.isAtWorkingTree ? "Retry" : "Latest",
                          action: { Task { viewModel.isAtWorkingTree ? await viewModel.reload() : await viewModel.goToWorkingTree() } },
                          onDismiss: dismiss)
                Spacer()
            }
            .padding(GitMetrics.Spacing.lg)
        } else if viewModel.lines.isEmpty {
            if viewModel.isLoadingBlame {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GitEmptyState(systemImage: "doc", title: "Empty File", subtitle: "This revision of the file has no lines.")
            }
        } else {
            BlameTable(viewModel: viewModel, showInHistory: host.showInHistory)
                .padding(.vertical, GitMetrics.Spacing.xs)
                .opacity(viewModel.isLoadingBlame ? 0.5 : 1)
        }
    }

    /// Back to picking a file, through the app when it routes them.
    private func dismiss() {
        viewModel.dismissError()
        host.pick?(nil)
    }
}
#endif
