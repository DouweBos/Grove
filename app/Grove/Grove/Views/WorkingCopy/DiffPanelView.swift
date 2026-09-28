// Views/WorkingCopy/DiffPanelView.swift
// Grove
//
// Right-hand card of the Changes tab: the selected file's diff with hunk actions,
// or the conflict resolver when the file is conflicted.

import SwiftUI

struct DiffPanelView: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @AppStorage(GrovePreferences.Key.mergeToolPath) private var mergeToolPath = ""

    var body: some View {
        VStack(spacing: 0) {
            if let entry = viewModel.selectedEntry {
                header(entry)
                content(entry)
            } else {
                EmptyStateView(
                    systemImage: viewModel.statusEntries.isEmpty ? "checkmark.seal" : "doc.text.magnifyingglass",
                    title: viewModel.statusEntries.isEmpty ? "Nothing to Commit" : "Select a File",
                    subtitle: viewModel.statusEntries.isEmpty
                        ? "Your working tree is clean."
                        : "Choose a file to see its changes."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panel()
    }

    // MARK: Header

    private func header(_ entry: StatusEntry) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            StatusIcon(status: entry.isConflicted ? .conflicted : (viewModel.showingStaged ? entry.indexStatus : entry.workdirStatus))
            Text(entry.fileName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .layoutPriority(1)
            Text(entry.directory)
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: Theme.Spacing.sm)
            if !entry.isConflicted { accessories }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: 44)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.border).frame(height: 0.5) }
    }

    /// Drops the side badge and stats before squeezing the file name in narrow windows.
    private var accessories: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Theme.Spacing.sm) { diffStats; sidePicker; textToggles }
            HStack(spacing: Theme.Spacing.sm) { sidePicker; textToggles }
            textToggles
        }
    }

    @ViewBuilder
    private var textToggles: some View {
        if let entry = viewModel.selectedEntry, !ImageDiffView.supports(path: entry.path) {
            HStack(spacing: Theme.Spacing.sm) { WrapLinesToggle(); whitespaceToggle }
        }
    }

    @ViewBuilder
    private var diffStats: some View {
        if let stats = viewModel.currentDiff?.stats, stats.additions + stats.deletions > 0 {
            HStack(spacing: Theme.Spacing.xs) {
                Text("+\(stats.additions)").foregroundStyle(Theme.added)
                Text("−\(stats.deletions)").foregroundStyle(Theme.deleted)
            }
            .font(.monoCaption)
            .fixedSize()
        }
    }

    @ViewBuilder
    private var sidePicker: some View {
        if viewModel.canSwitchDiffSide {
            Picker("Side", selection: Binding(get: { viewModel.selectedSide }, set: { side in Task { await viewModel.setDiffSide(side) } })) {
                Text("Unstaged").tag(DiffSide.unstaged)
                Text("Staged").tag(DiffSide.staged)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        } else {
            StatusBadge(title: viewModel.showingStaged ? "Staged" : "Unstaged",
                        symbol: viewModel.showingStaged ? "checkmark.circle" : "pencil",
                        tone: .neutral)
                .fixedSize()
        }
    }

    private var whitespaceToggle: some View {
        Button {
            Task { await viewModel.setIgnoreWhitespace(!viewModel.ignoreWhitespace) }
        } label: {
            Image(systemName: "text.word.spacing")
                .foregroundStyle(viewModel.ignoreWhitespace ? Theme.accent : Theme.textSecondary)
        }
        .buttonStyle(.borderless)
        .help(viewModel.ignoreWhitespace ? "Show Whitespace Changes" : "Ignore Whitespace Changes")
    }

    // MARK: Content

    @ViewBuilder
    private func content(_ entry: StatusEntry) -> some View {
        if entry.isConflicted {
            ConflictWizardView(
                versions: viewModel.conflictVersions,
                oursLabel: viewModel.operationContext?.oursLabel ?? "HEAD",
                theirsLabel: viewModel.operationContext?.theirsLabel ?? "Incoming",
                fileURL: viewModel.repository.path.appendingPathComponent(entry.path),
                onResolve: { side in Task { await viewModel.resolveConflict(taking: side) } },
                onOpenMergeTool: mergeToolPath.isEmpty ? nil : { Task { await viewModel.openInMergeTool(entry) } }
            )
        } else if ImageDiffView.supports(path: entry.path) {
            RepositoryImageDiffView(repository: viewModel.repository, path: entry.path,
                                    old: viewModel.showingStaged ? .commit("HEAD") : .index,
                                    new: viewModel.showingStaged ? .index : .workingTree,
                                    reloadToken: viewModel.diffLoadCount)
        } else if let diff = viewModel.currentDiff {
            DiffScrollView {
                DiffView(diff: diff, showingStaged: viewModel.showingStaged,
                         onHunkAction: supportsHunkActions(entry) ? { action, hunk, lines in
                             Task { await viewModel.performHunkAction(action, hunk: hunk, lines: lines) }
                         } : nil)
            }
            .id(diffIdentity(entry))
        } else if viewModel.isDiffLoading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyStateView(systemImage: "doc.questionmark", title: "No Diff Available",
                           subtitle: "The diff for this file could not be loaded.")
        }
    }

    /// Partial staging patches need a file that exists on both sides.
    private func supportsHunkActions(_ entry: StatusEntry) -> Bool {
        let status = viewModel.showingStaged ? entry.indexStatus : entry.workdirStatus
        return status == .modified
    }

    /// Resets scroll position and line selection when switching files or sides.
    private func diffIdentity(_ entry: StatusEntry) -> String {
        "\(entry.path)|\(viewModel.showingStaged)"
    }
}

#Preview("Diff Panel") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    DiffPanelView()
        .environment(vm)
        .frame(width: 640, height: 500)
        .padding()
        .background(Theme.background)
        .task {
            await vm.refresh()
            if let first = vm.statusEntries.first { await vm.select(first) }
        }
}
