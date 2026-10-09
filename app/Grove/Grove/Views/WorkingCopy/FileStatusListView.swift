// Views/WorkingCopy/FileStatusListView.swift
// Grove
//
// File list panel: Conflicts / Staged / Changes sections. A partially
// staged file appears in both Staged and Changes, each row acting on its own half.

import GroveKit
import SwiftUI

struct FileStatusListView: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @FocusState private var isListFocused: Bool
    /// Row frames in the list's content, so a drag can tell which row it's over.
    @State private var rowFrames: [FileRow: CGRect] = [:]
    @State private var dragRow: FileRow?

    static let coordinateSpace = "FileStatusList"

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Files", detail: fileCountDetail) {
                viewModePicker
                FilesPanelMenu()
            }
            content
        }
        .panel()
    }

    private var fileCountDetail: String? {
        let count = viewModel.statusEntries.count
        return count == 0 ? nil : "\(count) changed"
    }

    private var viewModePicker: some View {
        Menu {
            Picker("View", selection: Binding(get: { viewModel.fileViewMode }, set: { mode in Task { await viewModel.setFileViewMode(mode) } })) {
                ForEach(FileViewMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: viewModel.fileViewMode.symbol)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(Theme.textSecondary)
        .help("View Mode")
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.fileViewMode == .allFiles {
            AllFilesTreeView()
        } else if viewModel.statusEntries.isEmpty {
            if !viewModel.hasLoadedStatus {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // The diff panel carries the big "Nothing to Commit" state.
                Text("No changed files")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ScrollView {
                // Lazy: a deleted folder can put tens of thousands of files here at once.
                LazyVStack(alignment: .leading, spacing: 2) {
                    sections
                }
                .coordinateSpace(name: Self.coordinateSpace)
                .gesture(dragSelection)
                .padding(Theme.Spacing.sm)
            }
            .focusable()
            .focused($isListFocused)
            .focusEffectDisabled()
            .onKeyPress(.space) {
                Task { await viewModel.toggleStageOfSelection() }
                return .handled
            }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                let offset = press.key == .upArrow ? -1 : 1
                Task { await viewModel.moveSelection(by: offset, extend: press.modifiers.contains(.shift)) }
                return .handled
            }
        }
    }

    @ViewBuilder
    private var sections: some View {
        let conflicts = viewModel.conflictedFiles
        if !conflicts.isEmpty {
            FileSection(title: "Conflicts", entries: conflicts, side: .unstaged, isStagedSection: nil, focusList: focusList, recordFrame: recordFrame)
        }
        if !viewModel.showOnlyConflicts {
            let staged = viewModel.stagedFiles
            if !staged.isEmpty {
                FileSection(title: "Staged", entries: staged, side: .staged, isStagedSection: true, focusList: focusList, recordFrame: recordFrame) {
                    sectionButton("Unstage All") { await viewModel.unstageAll() }
                }
            }
            let unstaged = viewModel.unstagedFiles
            if !unstaged.isEmpty {
                FileSection(title: "Changes", entries: unstaged, side: .unstaged, isStagedSection: false, focusList: focusList, recordFrame: recordFrame) {
                    sectionButton("Stage All") { await viewModel.stageAll() }
                }
            }
        }
    }

    /// Dragging across rows selects from the row it started on to the one under the pointer, as in Finder.
    private var dragSelection: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { drag in
                guard let current = row(at: drag.location.y), current != dragRow else { return }
                // The first change also selects the row the drag started on, which ranges then grow from.
                let start = dragRow == nil ? row(at: drag.startLocation.y) : nil
                dragRow = current
                focusList()
                Task {
                    if let start, let entry = entry(for: start) {
                        await viewModel.click(entry, side: start.side, extend: false, toggle: false)
                    }
                    if current != start, let entry = entry(for: current) {
                        await viewModel.click(entry, side: current.side, extend: true, toggle: false)
                    }
                }
            }
            .onEnded { _ in dragRow = nil }
    }

    private func row(at y: CGFloat) -> FileRow? {
        rowFrames.first { $0.value.minY - 1 <= y && y <= $0.value.maxY + 1 }?.key
    }

    private func entry(for row: FileRow) -> StatusEntry? {
        viewModel.statusEntries.first { $0.path == row.path }
    }

    private func recordFrame(_ frame: CGRect, of row: FileRow) {
        if rowFrames[row] != frame { rowFrames[row] = frame }
    }

    /// A click focuses the list so Space and the arrow keys reach it.
    private func focusList() { isListFocused = true }

    private func sectionButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button(title) { Task { await action() } }
            .buttonStyle(.borderless)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.accent)
    }
}

#Preview("File List") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    FileStatusListView()
        .environment(vm)
        .frame(width: 320, height: 480)
        .padding()
        .background(Theme.background)
        .task { await vm.refresh() }
}
