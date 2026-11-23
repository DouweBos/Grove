// WorkingCopy/FileSection.swift
// GroveUIKit

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

/// What a section's rows tell the list they're in.
struct FileListActions {
    let focus: () -> Void
    let recordFrame: (CGRect, FileRow) -> Void
    let open: (String) -> Void
}

/// A labelled group of rows; flat or grouped by directory depending on the view mode.
struct FileSection<Accessory: View>: View {
    @Environment(\.gitStyle) private var style
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @Environment(\.workingCopySlots) private var slots

    let title: String
    let entries: [StatusEntry]
    let side: DiffSide
    /// Nil for conflicts, which are resolved rather than staged.
    let isStagedSection: Bool?
    let list: FileListActions
    @ViewBuilder var accessory: () -> Accessory

    /// Rows are direct children of the list's lazy stack, so only the visible ones are built.
    var body: some View {
        GitSectionLabel(title: title, count: entries.count, accessory: accessory)
            .padding(.horizontal, GitMetrics.Spacing.sm)
            .padding(.bottom, GitMetrics.Spacing.xs)
        if viewModel.fileViewMode == .treeModified {
            ForEach(viewModel.directoryGroups(entries), id: \.directory) { group in
                if !group.directory.isEmpty {
                    directoryHeader(group.directory)
                }
                ForEach(group.entries) { entry in
                    row(entry, showsDirectory: false)
                        .padding(.leading, group.directory.isEmpty ? 0 : GitMetrics.Spacing.lg)
                }
            }
        } else {
            ForEach(entries) { row($0, showsDirectory: true) }
        }
        Color.clear.frame(height: GitMetrics.Spacing.md - 2)
    }

    private func row(_ entry: StatusEntry, showsDirectory: Bool) -> some View {
        let status = entry.isConflicted ? FileStatus.conflicted : (side == .staged ? entry.indexStatus : entry.workdirStatus)
        let fileRow = FileRow(path: entry.path, side: side)
        return FileStatusRow(
            entry: entry,
            status: status,
            isStaged: isStagedSection ?? false,
            isSelected: viewModel.isSelected(entry, side: side),
            showsDirectory: showsDirectory,
            isLFS: viewModel.isLFS(entry),
            accessory: slots.rowAccessory?(entry),
            onToggleStage: isStagedSection.map { staged in
                { viewModel.act { staged ? await viewModel.unstageFile(entry) : await viewModel.stageFile(entry) } }
            }
        )
        .gesture(TapGesture(count: 2).onEnded { list.open(entry.path) })
        .simultaneousGesture(TapGesture().onEnded {
            list.focus()
            let modifiers = NSEvent.modifierFlags
            Task {
                await viewModel.click(entry, side: side, extend: modifiers.contains(.shift), toggle: modifiers.contains(.command))
            }
        })
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FileStatusList.coordinateSpace)) } action: {
            list.recordFrame($0, fileRow)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(entry.path)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { Task { await viewModel.select(entry, side: side) } }
        .contextMenu { FileContextMenu(entry: entry, side: side, isStagedSection: isStagedSection, open: list.open) }
    }

    private func directoryHeader(_ directory: String) -> some View {
        Label {
            Text(directory).font(style.monoCaption).lineLimit(1).truncationMode(.head)
        } icon: {
            Image(systemName: "folder").font(style.font(11))
        }
        .foregroundStyle(style.textSecondary)
        .padding(.horizontal, GitMetrics.Spacing.sm)
        .padding(.top, GitMetrics.Spacing.xs)
    }
}

extension FileSection where Accessory == EmptyView {
    init(title: String, entries: [StatusEntry], side: DiffSide, isStagedSection: Bool?, list: FileListActions) {
        self.init(title: title, entries: entries, side: side, isStagedSection: isStagedSection, list: list) { EmptyView() }
    }
}
#endif
