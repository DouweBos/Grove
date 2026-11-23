// WorkingCopy/FileStatusList.swift
// GroveUIKit
//
// The Files panel: Conflicts, Staged and Changes sections under a filter. A partly staged file is in both Staged
// and Changes, each row acting on its own half.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

struct FileStatusList: View {
    @Environment(\.gitStyle) private var style
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @Environment(\.workingCopyHost) private var host
    @Environment(\.workingCopySlots) private var slots
    @FocusState private var isListFocused: Bool
    /// Row frames in the list's content, so a drag can tell which row it's over; not observed, so recording them redraws nothing.
    @State private var rowFrames = RowFrames()
    @State private var dragRow: FileRow?
    @State private var filter = ""

    static let coordinateSpace = "GitFileStatusList"

    var body: some View {
        VStack(spacing: 0) {
            GitPanelHeader(title: "Files", detail: slots.filesDetail ?? fileCountDetail) {
                slots.filesHeader
                viewModePicker
                FilesPanelMenu()
            }
            if !viewModel.statusEntries.isEmpty || viewModel.fileViewMode == .allFiles || !filter.isEmpty {
                GitSearchField(placeholder: "Filter", text: filter, onChange: { filter = $0 })
                    .padding([.horizontal, .top], GitMetrics.Spacing.sm)
            }
            content
        }
        .gitPanel()
    }

    private var fileCountDetail: String? {
        let count = viewModel.statusEntries.count
        return count == 0 ? nil : "\(count) changed"
    }

    private var viewModePicker: some View {
        Menu {
            Picker("View", selection: Binding(get: { viewModel.fileViewMode },
                                              set: { mode in Task { await viewModel.setFileViewMode(mode) } })) {
                ForEach(FileViewMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: viewModel.fileViewMode.symbol).font(style.font(13))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(style.textSecondary)
        .gitClickable()
        .help("View Mode")
        .accessibilityLabel("View Mode")
    }

    @ViewBuilder
    private var content: some View {
        let groups = Groups(viewModel, filter: filter)
        if viewModel.fileViewMode == .allFiles {
            AllFilesTree(filter: filter)
        } else if groups.isEmpty, !viewModel.statusEntries.isEmpty {
            Text("Nothing matches \u{201C}\(filter)\u{201D}")
                .font(style.font(13))
                .foregroundStyle(style.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(GitMetrics.Spacing.lg)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.statusEntries.isEmpty {
            Group {
                if !viewModel.hasLoadedStatus {
                    ProgressView().controlSize(.small)
                } else {
                    // The detail carries the big "Nothing to Commit" state.
                    Text("No changed files").font(style.font(13)).foregroundStyle(style.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    // Lazy: a deleted folder can put tens of thousands of files here at once.
                    LazyVStack(alignment: .leading, spacing: 2) {
                        sections(groups)
                    }
                    .coordinateSpace(name: Self.coordinateSpace)
                    .gesture(dragSelection)
                    .padding(GitMetrics.Spacing.sm)
                }
                // Arrow keys can move the selection off screen; the list follows it.
                .onChange(of: viewModel.fileSelection.focus) { _, focus in
                    if let focus { proxy.scrollTo(focus) }
                }
            }
            .focusable()
            .focused($isListFocused)
            .focusEffectDisabled()
            .onKeyPress(.space) {
                viewModel.act { await viewModel.toggleStageOfSelection() }
                return .handled
            }
            .onKeyPress(.return) { openFocused() }
            // Edit > Select All, so ⌘A reaches the list only while it has focus, not the commit message.
            .onCommand(#selector(NSResponder.selectAll(_:))) {
                Task { await viewModel.selectAllFiles() }
            }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                let offset = press.key == .upArrow ? -1 : 1
                Task { await viewModel.moveSelection(by: offset, extend: press.modifiers.contains(.shift)) }
                return .handled
            }
        }
    }

    @ViewBuilder
    private func sections(_ groups: Groups) -> some View {
        if !groups.conflicts.isEmpty {
            FileSection(title: "Conflicts", entries: groups.conflicts, side: .unstaged, isStagedSection: nil, list: listActions)
        }
        if !groups.staged.isEmpty {
            FileSection(title: "Staged", entries: groups.staged, side: .staged, isStagedSection: true, list: listActions) {
                sectionButton("Unstage All") { await viewModel.unstageAll() }
            }
        }
        if !groups.unstaged.isEmpty {
            FileSection(title: "Changes", entries: groups.unstaged, side: .unstaged, isStagedSection: false, list: listActions) {
                sectionButton("Stage All") { await viewModel.stageAll() }
            }
        }
    }

    /// The sections' files that match the filter, a path's part in any case.
    struct Groups {
        let conflicts: [StatusEntry]
        let staged: [StatusEntry]
        let unstaged: [StatusEntry]

        var isEmpty: Bool { conflicts.isEmpty && staged.isEmpty && unstaged.isEmpty }

        @MainActor
        init(_ viewModel: WorkingCopyViewModel, filter: String) {
            let onlyConflicts = viewModel.showOnlyConflicts
            conflicts = Self.matching(viewModel.conflictedFiles, filter)
            staged = onlyConflicts ? [] : Self.matching(viewModel.stagedFiles, filter)
            unstaged = onlyConflicts ? [] : Self.matching(viewModel.unstagedFiles, filter)
        }

        static func matching(_ entries: [StatusEntry], _ filter: String) -> [StatusEntry] {
            let query = filter.trimmingCharacters(in: .whitespaces)
            return query.isEmpty ? entries : entries.filter { $0.path.localizedCaseInsensitiveContains(query) }
        }
    }

    private var listActions: FileListActions {
        FileListActions(focus: { isListFocused = true }, recordFrame: recordFrame, open: open)
    }

    /// Return opens the file the diff shows, as a double-click does.
    private func openFocused() -> KeyPress.Result {
        guard let path = viewModel.fileSelection.focus?.path, host.openFile != nil else { return .ignored }
        open(path)
        return .handled
    }

    private func open(_ path: String) {
        guard let entry = viewModel.statusEntries.first(where: { $0.path == path }), entry.existsOnDisk else { return }
        host.openFile?(path)
    }

    /// Dragging across rows selects from the row it started on to the one under the pointer, as in Finder.
    private var dragSelection: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.coordinateSpace))
            .onChanged { drag in
                guard let current = row(at: drag.location.y), current != dragRow else { return }
                // The first change also selects the row the drag started on, which ranges then grow from.
                let start = dragRow == nil ? row(at: drag.startLocation.y) : nil
                dragRow = current
                isListFocused = true
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
        rowFrames.frames.first { $0.value.minY - 1 <= y && y <= $0.value.maxY + 1 }?.key
    }

    private func entry(for row: FileRow) -> StatusEntry? {
        viewModel.statusEntries.first { $0.path == row.path }
    }

    private func recordFrame(_ frame: CGRect, of row: FileRow) {
        rowFrames.frames[row] = frame
    }

    private func sectionButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button(title) { viewModel.act(action) }
            .buttonStyle(.borderless)
            .font(style.font(12, .medium))
            .foregroundStyle(style.accent)
            .gitClickable()
    }
}

final class RowFrames {
    var frames: [FileRow: CGRect] = [:]
}

extension StatusEntry {
    /// Still in the working tree, so it can be opened, renamed or moved to the Trash.
    var existsOnDisk: Bool {
        workdirStatus != .deleted && !(indexStatus == .deleted && workdirStatus == .unmodified)
    }
}
#endif
