// WorkingCopy/FileContextMenu.swift
// GroveUIKit
//
// A Changes row's menu; inside a multi-selection it acts on all of it.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

struct FileContextMenu: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @Environment(\.workingCopyHost) private var host
    @Environment(\.workingCopySlots) private var slots
    @Environment(\.gitHost) private var gitHost
    @Environment(\.gitFeatures) private var features
    let entry: StatusEntry
    let side: DiffSide
    let isStagedSection: Bool?
    let open: (String) -> Void

    var body: some View {
        let entries = viewModel.actionEntries(for: entry, side: side)
        if let staged = isStagedSection {
            stagingItems(staged: staged, entries: entries)
        } else if entries.count == 1 {
            Button("Resolve") { Task { await viewModel.select(entry) } }
            if let openInMergeTool = host.openInMergeTool {
                Button("Open in Merge Tool") { openInMergeTool(entry) }
            }
        }
        if entries.count == 1, entry.existsOnDisk, host.openFile != nil {
            Button("Open File") { open(entry.path) }
        }
        lfsItems(entries)
        Divider()
        Button(entries.count > 1 ? "Copy \(entries.count) Paths" : "Copy Path") {
            gitHost.copy(entries.map(\.path).joined(separator: "\n"))
        }
        Button("Reveal in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(entries.map { viewModel.repository.path.appendingPathComponent($0.path) })
        }
        .requires(.reveal)
        Divider()
        FileActionsMenu(entries: entries)
        if let rowMenu = slots.rowMenu {
            Divider()
            rowMenu(entry, entries)
        }
        if isStagedSection != nil {
            Divider()
            Button(entries.count > 1 ? "Discard Changes in \(entries.count) Files" : "Discard Changes", role: .destructive) {
                viewModel.requestDiscard(entries)
            }
        }
    }

    @ViewBuilder
    private func stagingItems(staged: Bool, entries: [StatusEntry]) -> some View {
        let row = FileRow(path: entry.path, side: side)
        // Inside a multi-selection it acts on this section's part of it.
        let rows: Set<FileRow> = viewModel.fileSelection.contains(row) ? viewModel.fileSelection.rows.filter { $0.side == side } : [row]
        let verb = staged ? "Unstage" : "Stage"
        Button(rows.count > 1 ? "\(verb) \(rows.count) Files" : verb) {
            viewModel.act { await viewModel.toggleStage(rows) }
        }
        if let openInDiffTool = host.openInDiffTool, entries.count == 1 {
            Button("Open in Diff Tool") { openInDiffTool(entry, side) }
        }
        let patchEntries = viewModel.patchEntries(for: entry, side: side)
        Button(patchEntries.count > 1 ? "Create Patch from \(patchEntries.count) Files" : "Create Patch") {
            Task { await createPatch(patchEntries, side: side, viewModel: viewModel, host: host) }
        }
        .requires(.export)
        if let present = host.present {
            Button(entries.count > 1 ? "Stash \(entries.count) Files" : "Stash") {
                present(.stash(paths: entries.map(\.path)))
            }
        }
    }

    @ViewBuilder
    private func lfsItems(_ entries: [StatusEntry]) -> some View {
        let candidates = viewModel.lfsCandidates(entries)
        if !candidates.isEmpty, !viewModel.lfs.status.isMissing {
            Menu("Track with Git LFS") {
                Button(candidates.count > 1 ? "These \(candidates.count) Files" : "This File") {
                    viewModel.act { await viewModel.trackWithLFS(candidates, byExtension: false) }
                }
                if let pattern = WorkingCopyViewModel.lfsExtensionPattern(for: candidates) {
                    Button("All \(pattern) Files") {
                        viewModel.act { await viewModel.trackWithLFS(candidates, byExtension: true) }
                    }
                }
            }
        }
    }
}
#endif
