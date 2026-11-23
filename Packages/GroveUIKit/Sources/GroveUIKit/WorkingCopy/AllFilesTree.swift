// WorkingCopy/AllFilesTree.swift
// GroveUIKit
//
// Every tracked file grouped by directory; changed files carry their status letter and the Changes menu.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

struct AllFilesTree: View {
    @Environment(\.gitStyle) private var style
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @Environment(\.workingCopyHost) private var host
    @Environment(\.workingCopySlots) private var slots
    @Environment(\.gitHost) private var gitHost
    var filter = ""
    @State private var expanded: Set<String> = [""]

    var body: some View {
        let entriesByPath = Dictionary(viewModel.statusEntries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Self.groups(viewModel.allTrackedFiles, entries: viewModel.statusEntries, filter: filter),
                        id: \.directory) { group in
                    if !group.directory.isEmpty {
                        directoryRow(group)
                    }
                    // A filter shows every match rather than only open folders'.
                    if expanded.contains(group.directory) || !filter.isEmpty {
                        ForEach(group.paths, id: \.self) { path in
                            fileRow(path, entry: entriesByPath[path], indented: !group.directory.isEmpty)
                        }
                    }
                }
            }
            .padding(GitMetrics.Spacing.sm)
        }
    }

    private func directoryRow(_ group: FolderGroup) -> some View {
        let isOpen = expanded.contains(group.directory)
        return Button {
            if isOpen { expanded.remove(group.directory) } else { expanded.insert(group.directory) }
        } label: {
            HStack(spacing: GitMetrics.Spacing.xs) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(style.font(9, .semibold))
                    .frame(width: 12)
                Image(systemName: "folder").font(style.font(11))
                Text(group.directory).font(style.monoCaption).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 0)
                Text("\(group.paths.count)").font(style.monoCaption)
            }
            .foregroundStyle(style.textSecondary)
            .padding(.horizontal, GitMetrics.Spacing.sm)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gitClickable()
    }

    private func fileRow(_ path: String, entry: StatusEntry?, indented: Bool) -> some View {
        let isSelected = entry != nil && viewModel.selectedEntry?.path == path
        return HStack(spacing: GitMetrics.Spacing.sm) {
            GitStatusIcon(status: entry.map { $0.workdirStatus != .unmodified ? $0.workdirStatus : $0.indexStatus } ?? .unmodified)
            Text((path as NSString).lastPathComponent)
                .font(style.font(13, .regular, .monospaced))
                .foregroundStyle(entry == nil ? style.textSecondary : style.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GitMetrics.Spacing.sm)
        .padding(.vertical, 3)
        .padding(.leading, indented ? GitMetrics.Spacing.lg : 0)
        .background(isSelected ? style.selectionFill : .clear, in: RoundedRectangle(cornerRadius: GitMetrics.Radius.row, style: .continuous))
        .contentShape(Rectangle())
        .gitClickable(entry != nil || host.openFile != nil)
        .help(path)
        .gesture(TapGesture(count: 2).onEnded { host.openFile?(path) })
        .simultaneousGesture(TapGesture().onEnded {
            guard let entry else { return }
            Task { await viewModel.select(entry) }
        })
        .contextMenu {
            if let entry {
                let side: DiffSide = entry.isConflicted || entry.workdirStatus != .unmodified ? .unstaged : .staged
                FileContextMenu(entry: entry, side: side, isStagedSection: entry.isConflicted ? nil : side == .staged,
                                open: { host.openFile?($0) })
            } else {
                trackedMenu(path)
            }
        }
    }

    @ViewBuilder
    private func trackedMenu(_ path: String) -> some View {
        if let openFile = host.openFile {
            Button("Open File") { openFile(path) }
        }
        Button("Copy Path") { gitHost.copy(path) }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([viewModel.repository.path.appendingPathComponent(path)])
        }
        .requires(.reveal)
        if let menu = slots.trackedFileMenu {
            Divider()
            menu(path)
        }
    }

    struct FolderGroup: Equatable {
        let directory: String
        let paths: [String]
    }

    /// Tracked files plus the untracked ones matching `filter`, in Finder's order, by folder.
    static func groups(_ tracked: [String], entries: [StatusEntry], filter: String = "") -> [FolderGroup] {
        let untracked = entries.filter { $0.workdirStatus == .untracked }.map(\.path)
        let query = filter.trimmingCharacters(in: .whitespaces)
        let paths = Set(tracked).union(untracked).filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        return Dictionary(grouping: paths) { ($0 as NSString).deletingLastPathComponent }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { FolderGroup(directory: $0.key, paths: $0.value.sorted { $0.localizedStandardCompare($1) == .orderedAscending }) }
    }
}
#endif
