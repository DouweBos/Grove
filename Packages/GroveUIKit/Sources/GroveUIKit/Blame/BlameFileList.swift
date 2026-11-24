// Blame/BlameFileList.swift
// GroveUIKit
//
// The tracked files, filtered as you type.

#if os(macOS)
import GroveKit
import SwiftUI

struct BlameFileList: View {
    @Environment(\.gitStyle) private var style
    let viewModel: BlameViewModel
    let host: GitBlameHost
    let pick: (String?) -> Void

    var body: some View {
        VStack(spacing: 0) {
            GitPanelHeader(title: "Files", detail: "\(viewModel.filteredFiles.count)") {
                Button { Task { await viewModel.reloadFiles() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .gitClickable()
                    .help("Reload File List")
                    .accessibilityLabel("Reload File List")
            }
            GitSearchField(placeholder: "Filter files", text: viewModel.filterText, onChange: viewModel.setFilter)
                .padding([.horizontal, .top], GitMetrics.Spacing.sm)
            if viewModel.isLoadingFiles && viewModel.trackedFiles.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredFiles.isEmpty {
                GitEmptyState(systemImage: "doc.text.magnifyingglass", title: "No Matching Files",
                              subtitle: viewModel.trackedFiles.isEmpty ? "This repository has no tracked files." : nil)
            } else {
                GitSelectableList(items: viewModel.filteredFiles.map(BlameFileItem.init), selection: viewModel.selectedFile,
                                  onSelect: { pick($0.id) }) { row($0.id) }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .gitPanel()
    }

    private func row(_ path: String) -> some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            if let icon = host.fileIcon { icon(path) }
            VStack(alignment: .leading, spacing: 2) {
                Text((path as NSString).lastPathComponent)
                    .font(style.font(13, .medium))
                    .foregroundStyle(style.textPrimary)
                    .lineLimit(1)
                let directory = (path as NSString).deletingLastPathComponent
                Text(directory.isEmpty ? "/" : directory)
                    .font(style.monoCaption)
                    .foregroundStyle(style.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
    }
}

private struct BlameFileItem: Identifiable {
    let id: String
}
#endif
