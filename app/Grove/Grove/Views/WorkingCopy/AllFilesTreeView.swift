// Views/WorkingCopy/AllFilesTreeView.swift
// Grove
//
// Every tracked file grouped by directory; changed files carry their status letter.

import GroveKit
import SwiftUI

struct AllFilesTreeView: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @State private var expanded: Set<String> = [""]

    var body: some View {
        let entriesByPath = Dictionary(viewModel.statusEntries.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(groups, id: \.directory) { group in
                    if !group.directory.isEmpty {
                        directoryRow(group)
                    }
                    if expanded.contains(group.directory) {
                        ForEach(group.paths, id: \.self) { path in
                            fileRow(path, entry: entriesByPath[path], indented: !group.directory.isEmpty)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.sm)
        }
    }

    private func directoryRow(_ group: FolderGroup) -> some View {
        let isOpen = expanded.contains(group.directory)
        return Button {
            if isOpen { expanded.remove(group.directory) } else { expanded.insert(group.directory) }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 12)
                Image(systemName: "folder").font(.system(size: 11))
                Text(group.directory).font(.monoCaption).lineLimit(1).truncationMode(.head)
                Spacer(minLength: 0)
                Text("\(group.paths.count)").font(.monoCaption)
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fileRow(_ path: String, entry: StatusEntry?, indented: Bool) -> some View {
        let isSelected = entry != nil && viewModel.selectedEntry?.path == path
        return HStack(spacing: Theme.Spacing.sm) {
            StatusIcon(status: entry.map { $0.workdirStatus != .unmodified ? $0.workdirStatus : $0.indexStatus } ?? .unmodified)
            Text((path as NSString).lastPathComponent)
                .font(.monoBody)
                .foregroundStyle(entry == nil ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 3)
        .padding(.leading, indented ? Theme.Spacing.lg : 0)
        .background(isSelected ? Theme.selectionFill : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            guard let entry else { return }
            Task { await viewModel.select(entry) }
        }
    }

    private struct FolderGroup {
        let directory: String
        let paths: [String]
    }

    private var groups: [FolderGroup] {
        Dictionary(grouping: viewModel.allTrackedFiles) { ($0 as NSString).deletingLastPathComponent }
            .sorted { $0.key < $1.key }
            .map { FolderGroup(directory: $0.key, paths: $0.value.sorted()) }
    }
}

#Preview {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    AllFilesTreeView()
        .environment(vm)
        .frame(width: 320, height: 480)
        .panel()
        .padding()
        .background(Theme.background)
        .task { await vm.refresh() }
}
