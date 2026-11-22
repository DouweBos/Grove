// Views/WorkingCopy/DiffPanelView.swift
// Grove
//
// Right-hand card of the Changes tab: the selected file's diff with hunk actions,
// or the conflict resolver when the file is conflicted.

import GroveKit
import GroveUIKit
import SwiftUI

struct DiffPanelView: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @AppStorage(GrovePreferences.Key.mergeToolPath) private var mergeToolPath = ""
    private var settings = DiffSettings()

    var body: some View {
        VStack(spacing: 0) {
            if let entry = viewModel.selectedEntry {
                if entry.isConflicted {
                    GitDiffFileHeader(path: entry.path, status: .conflicted)
                    conflict(entry)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    diff(entry)
                }
            } else {
                GitEmptyState(
                    systemImage: viewModel.statusEntries.isEmpty ? "checkmark.seal" : "doc.text.magnifyingglass",
                    title: viewModel.statusEntries.isEmpty ? "Nothing to Commit" : "Select a File",
                    subtitle: viewModel.statusEntries.isEmpty
                        ? "Your working tree is clean."
                        : "Choose a file to see its changes."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gitPanel()
    }

    // MARK: Diff

    private func diff(_ entry: StatusEntry) -> some View {
        let showingStaged = viewModel.showingStaged
        return GitDiffPane(
            diff: viewModel.currentDiff,
            path: entry.path,
            status: showingStaged ? entry.indexStatus : entry.workdirStatus,
            isLoading: viewModel.isDiffLoading,
            options: settings.options,
            staging: Self.offersHunkActions(entry, showingStaged: showingStaged) ? staging : nil,
            sideSwitch: GitDiffSideSwitch(
                side: viewModel.selectedSide,
                select: viewModel.canSwitchDiffSide ? { side in Task { await viewModel.setDiffSide(side) } } : nil),
            ignoresWhitespace: Binding(get: { viewModel.ignoreWhitespace },
                                       set: { ignores in Task { await viewModel.setIgnoreWhitespace(ignores) } }),
            images: GitDiffImages(repository: viewModel.repository,
                                  old: showingStaged ? .commit("HEAD") : .index,
                                  new: showingStaged ? .index : .workingTree,
                                  reloadToken: viewModel.diffLoadCount))
    }

    private var staging: GitDiffStaging {
        GitDiffStaging(side: viewModel.selectedSide) { action, hunk, lines in
            Task { await viewModel.performHunkAction(action, hunk: hunk, lines: lines) }
        }
    }

    static func offersHunkActions(_ entry: StatusEntry, showingStaged: Bool) -> Bool {
        (showingStaged ? entry.indexStatus : entry.workdirStatus).supportsHunkActions
    }

    // MARK: Conflict

    private func conflict(_ entry: StatusEntry) -> some View {
        ConflictWizardView(
            versions: viewModel.conflictVersions,
            oursLabel: viewModel.operationContext?.oursLabel ?? "HEAD",
            theirsLabel: viewModel.operationContext?.theirsLabel ?? "Incoming",
            fileURL: viewModel.repository.path.appendingPathComponent(entry.path),
            onResolve: { side in Task { await viewModel.resolveConflict(taking: side) } },
            onOpenMergeTool: mergeToolPath.isEmpty ? nil : { Task { await viewModel.openInMergeTool(entry) } }
        )
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
