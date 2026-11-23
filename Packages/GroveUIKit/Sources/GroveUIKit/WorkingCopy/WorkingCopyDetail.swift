// WorkingCopy/WorkingCopyDetail.swift
// GroveUIKit
//
// The Changes screen's right card: the selected file's diff with hunk actions, or the resolver for a conflict.

#if os(macOS)
import GroveKit
import SwiftUI

/// The app's replacement for the diff unless a conflict is picked, else the kit's detail.
struct WorkingCopyDetailArea: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @Environment(\.workingCopySlots) private var slots

    var body: some View {
        if let replacement = slots.replacement, viewModel.selectedEntry?.isConflicted != true {
            replacement.detail.gitPanel()
        } else {
            WorkingCopyDetail()
        }
    }
}

struct WorkingCopyDetail: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @Environment(\.workingCopySlots) private var slots
    @Environment(\.workingCopyHost) private var host
    @State private var layout = GitDiffLayout.inline
    @State private var wrapsLines = false
    @State private var imageMode = GitImageDiffMode.sideBySide

    var body: some View {
        VStack(spacing: 0) {
            if let entry = viewModel.selectedEntry {
                if entry.isConflicted {
                    GitConflictResolver(entry: entry)
                } else if let diff = slots.diff {
                    diff(entry)
                } else {
                    self.diff(entry)
                }
            } else {
                GitEmptyState(
                    systemImage: viewModel.statusEntries.isEmpty ? "checkmark.seal" : "doc.text.magnifyingglass",
                    title: viewModel.statusEntries.isEmpty ? "Nothing to Commit" : "Select a File",
                    subtitle: viewModel.statusEntries.isEmpty ? "Your working tree is clean." : "Choose a file to see its changes.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gitPanel()
    }

    private func diff(_ entry: StatusEntry) -> some View {
        let staged = viewModel.showingStaged
        return GitDiffPane(
            diff: viewModel.currentDiff,
            path: entry.path,
            status: staged ? entry.indexStatus : entry.workdirStatus,
            isLoading: viewModel.isDiffLoading,
            options: host.diffOptions ?? GitDiffOptions(layout: $layout, wrapsLines: $wrapsLines, imageMode: $imageMode),
            staging: Self.offersHunkActions(entry, showingStaged: staged) ? Self.staging(viewModel) : nil,
            sideSwitch: Self.sideSwitch(viewModel),
            ignoresWhitespace: Binding(get: { viewModel.ignoreWhitespace },
                                       set: { ignores in Task { await viewModel.setIgnoreWhitespace(ignores) } }),
            images: Self.images(viewModel))
    }

    static func offersHunkActions(_ entry: StatusEntry, showingStaged: Bool) -> Bool {
        (showingStaged ? entry.indexStatus : entry.workdirStatus).supportsHunkActions
    }
}

extension WorkingCopyDetail {
    static func staging(_ viewModel: WorkingCopyViewModel) -> GitDiffStaging {
        GitDiffStaging(side: viewModel.selectedSide) { action, hunk, lines in
            viewModel.act { await viewModel.performHunkAction(action, hunk: hunk, lines: lines) }
        }
    }

    static func sideSwitch(_ viewModel: WorkingCopyViewModel) -> GitDiffSideSwitch {
        GitDiffSideSwitch(side: viewModel.selectedSide,
                          select: viewModel.canSwitchDiffSide ? { side in Task { await viewModel.setDiffSide(side) } } : nil)
    }

    static func images(_ viewModel: WorkingCopyViewModel) -> GitDiffImages {
        let staged = viewModel.showingStaged
        return GitDiffImages(repository: viewModel.repository, old: staged ? .commit("HEAD") : .index,
                             new: staged ? .index : .workingTree, reloadToken: viewModel.diffLoadCount)
    }
}
#endif
