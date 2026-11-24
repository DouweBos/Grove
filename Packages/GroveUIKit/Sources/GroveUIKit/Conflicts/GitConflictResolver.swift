// Conflicts/GitConflictResolver.swift
// GroveUIKit
//
// A conflicted file: both versions side by side, each keepable whole, over the merged result
// as it sits in the working tree, markers and all, to edit and save.

#if os(macOS)
import GroveKit
import SwiftUI

struct GitConflictResolver: View {
    @Environment(\.gitStyle) private var style
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @Environment(\.workingCopyHost) private var host
    let entry: StatusEntry
    @State private var editor = ConflictEditor()
    @State private var result = ConflictResult.loading
    @State private var isSaving = false
    @State private var width: CGFloat = .infinity
    @State private var resultWidth: CGFloat = .infinity

    var body: some View {
        VStack(alignment: .leading, spacing: GitMetrics.Spacing.md) {
            header
            VSplitView {
                // Side by side while each side keeps a readable width, else one above the other. A width check, not
                // ViewThatFits: that builds both layouts of two 100k-line panels.
                Group {
                    if width < 520 * style.fontScale {
                        VStack(spacing: GitMetrics.Spacing.sm) { sides }
                    } else {
                        HStack(spacing: GitMetrics.Spacing.md) { sides }
                    }
                }
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
                .padding(.bottom, GitMetrics.Spacing.sm)
                .frame(minHeight: 140 * style.fontScale)
                mergedEditor
                    .padding(.top, GitMetrics.Spacing.sm)
                    .frame(minHeight: 180 * style.fontScale)
            }
        }
        .padding(GitMetrics.Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: entry.path) { await load() }
    }

    @ViewBuilder
    private var sides: some View {

        ConflictVersionPanel(side: .ours, branchName: viewModel.operationContext?.oursLabel ?? "HEAD",
                             content: sideContent(\.ours), isBusy: isBusy) { take(.ours) }
        ConflictVersionPanel(side: .theirs, branchName: viewModel.operationContext?.theirsLabel ?? "Incoming",
                             content: sideContent(\.theirs), isBusy: isBusy) { take(.theirs) }
    }

    private var isBusy: Bool { isSaving || viewModel.isDiffLoading }

    /// Nil while loading, then each side's text, or nil where that side deleted the file.
    private func sideContent(_ side: KeyPath<ConflictVersions, String?>) -> String?? {
        guard let versions = viewModel.conflictVersions else { return viewModel.isDiffLoading ? nil : .some(nil) }
        return .some(versions[keyPath: side])
    }

    private var header: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(style.warning)
            Text(result.text == nil && result != .loading
                 ? "Both sides changed \(entry.fileName). Keep one version."
                 : "Both sides changed \(entry.fileName). Keep one version, or edit the result and save it.")
                .font(style.font(13))
                .foregroundStyle(style.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: GitMetrics.Spacing.sm)
            if let openFile = host.openFile {
                Button("Open File") { openFile(entry.path) }
                    .gitClickable()
                    .help("Edit the conflict markers in an editor")
            }
            if let openInMergeTool = host.openInMergeTool {
                Button("Open in Merge Tool") { openInMergeTool(entry) }
                    .gitClickable()
                    .help("Resolve in your merge tool, then save the result here")
            }
        }
    }

    private func resultHeader(path: Bool, compact: Bool) -> some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            Text("Result").font(style.sectionLabel).foregroundStyle(style.textSecondary).fixedSize()
            if path {
                Text(entry.path)
                    .font(style.monoCaption)
                    .foregroundStyle(style.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(minWidth: 60, alignment: .leading)
            }
            Spacer(minLength: GitMetrics.Spacing.sm)
            if result.text != nil, editor.hasMarkers {
                if compact {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(style.warning)
                        .accessibilityLabel("Markers Left")
                        .help("Conflict markers are still in the result")
                } else {
                    GitStatusBadge(title: "Markers Left", symbol: "exclamationmark.triangle", tone: .caution)
                        .fixedSize()
                        .help("Conflict markers are still in the result")
                }
            }
            Button("Revert") { Task { await load() } }
                .fixedSize()
                .disabled(result.text == nil || !editor.isEdited || isSaving)
                .gitClickable()
                .help("Back to the file as it is on disk")
            Button(compact ? "Save" : "Save and Mark Resolved") { save() }
                .fixedSize()
                .buttonStyle(.borderedProminent)
                .disabled(result.text == nil || isBusy)
                .gitClickable()
                .help("Save and mark resolved")
        }
    }

    private var mergedEditor: some View {
        VStack(spacing: 0) {
            // Narrow, the path, then the badge's words and the button's give way; the buttons never truncate.
            resultHeader(path: resultWidth >= 520 * style.fontScale, compact: resultWidth < 400 * style.fontScale)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self, of: \.size.width) { resultWidth = $0 }
            .controlSize(.small)
            .padding(.horizontal, GitMetrics.Spacing.md)
            .frame(height: 40 * style.fontScale)
            .overlay(alignment: .bottom) { Rectangle().fill(style.border).frame(height: 0.5) }
            resultBody.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .gitPanel()
    }

    @ViewBuilder
    private var resultBody: some View {
        switch result {
        case .loading:
            ProgressView().controlSize(.small)
        case .loaded:
            ConflictTextView(editor: editor)
        case .unreadable(let reason):
            GitEmptyState(systemImage: "exclamationmark.triangle", title: "Couldn\u{2019}t Read the Result", subtitle: reason,
                          actionTitle: "Try Again") { Task { await load() } }
        }
    }

    private func load() async {
        result = .loading
        let read = await ConflictResult.read(entry.path, from: viewModel.repository)
        guard !Task.isCancelled else { return }
        editor.load(read.text ?? "")
        result = read
    }

    private func take(_ side: ConflictSide) {
        viewModel.act { await viewModel.resolveConflict(taking: side) }
    }

    /// Only text read from the file is ever written back: an unreadable result has nothing to save.
    private func save() {
        guard result.text != nil, !isSaving else { return }
        isSaving = true
        viewModel.act {
            let contents = await editor.currentText()
            await viewModel.saveConflictResolution(entry, contents: contents)
            isSaving = false
        }
    }
}
#endif
