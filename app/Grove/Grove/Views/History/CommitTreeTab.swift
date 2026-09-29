// Views/History/CommitTreeTab.swift
// Grove

import SwiftUI

/// Every file in the repository as of the selected commit, with this commit's changes marked.
struct CommitTreeTab: View {
    @Environment(HistoryViewModel.self) private var viewModel
    /// Folders the user flipped away from the default (open only when they contain changes).
    @State private var toggled: Set<String> = []

    var body: some View {
        if viewModel.isLoadingTree && viewModel.treeFiles.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(Theme.Spacing.xl)
        } else {
            let tree = FileTreeNode.build(from: viewModel.treeFiles)
            let changed = Dictionary(viewModel.commitDiffs.map { ($0.path, $0.status) }, uniquingKeysWith: { a, _ in a })
            HStack {
                SectionLabel(title: "\(viewModel.treeFiles.count) file\(viewModel.treeFiles.count == 1 ? "" : "s")")
                Text("\(changed.count) changed").font(.monoCaption).foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.xs)
            let changedFolders = Self.ancestorFolders(of: changed.keys)
            let isExpanded = { (path: String) in changedFolders.contains(path) != toggled.contains(path) }
            ForEach(tree.visibleRows(isExpanded: isExpanded)) { row in
                treeRow(row, status: changed[row.path], isExpanded: row.isDirectory && isExpanded(row.path))
            }
        }
    }

    private static func ancestorFolders(of paths: some Sequence<String>) -> Set<String> {
        var folders: Set<String> = []
        for path in paths {
            var parts = path.split(separator: "/").dropLast()
            while !parts.isEmpty {
                folders.insert(parts.joined(separator: "/"))
                parts = parts.dropLast()
            }
        }
        return folders
    }

    private func treeRow(_ row: FileTreeNode.Row, status: FileStatus?, isExpanded: Bool) -> some View {
        Button {
            if row.isDirectory {
                if toggled.contains(row.path) { toggled.remove(row.path) } else { toggled.insert(row.path) }
            } else if status != nil {
                viewModel.revealInChangeset(row.path)
            }
        } label: {
            HStack(spacing: 6) {
                if row.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10)
                        .foregroundStyle(Theme.textSecondary)
                }
                Image(systemName: row.isDirectory ? "folder.fill" : "doc")
                    .font(.system(size: 12))
                    .foregroundStyle(row.isDirectory ? Theme.info : Theme.textSecondary)
                    .frame(width: 16)
                Text(row.name)
                    .font(.system(size: 13, weight: status == nil ? .regular : .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.sm)
                if let status { CommitFileStatusBadge(status: status) }
            }
            .padding(.leading, Theme.Spacing.lg + CGFloat(row.depth) * 16 + (row.isDirectory ? 0 : 16))
            .padding(.trailing, Theme.Spacing.lg)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !row.isDirectory {
                Button("Show File History\u{2026}") { viewModel.request(.fileHistory(row.path)) }
            }
            Button("Copy Path") {
                GroveClipboard.copy(row.path)
            }
        }
    }
}

/// Directory tree built from flat `ls-tree` paths.
struct FileTreeNode {
    var name: String
    var path: String
    var children: [String: FileTreeNode] = [:]
    var isDirectory: Bool

    struct Row: Identifiable {
        let path: String
        let name: String
        let depth: Int
        let isDirectory: Bool
        var id: String { path }
    }

    static func build(from paths: [String]) -> FileTreeNode {
        var root = FileTreeNode(name: "", path: "", isDirectory: true)
        for path in paths {
            root.insert(path.split(separator: "/").map(String.init), prefix: "")
        }
        return root
    }

    private mutating func insert(_ components: [String], prefix: String) {
        guard let first = components.first else { return }
        let childPath = prefix.isEmpty ? first : "\(prefix)/\(first)"
        let isLeaf = components.count == 1
        var child = children[first] ?? FileTreeNode(name: first, path: childPath, isDirectory: !isLeaf)
        if !isLeaf { child.insert(Array(components.dropFirst()), prefix: childPath) }
        children[first] = child
    }

    /// Depth-first rows, folders before files, skipping the contents of collapsed folders.
    func visibleRows(isExpanded: (String) -> Bool, depth: Int = 0) -> [Row] {
        let sorted = children.values.sorted {
            $0.isDirectory != $1.isDirectory ? $0.isDirectory : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return sorted.flatMap { child -> [Row] in
            let row = Row(path: child.path, name: child.name, depth: depth, isDirectory: child.isDirectory)
            guard child.isDirectory, isExpanded(child.path) else { return [row] }
            return [row] + child.visibleRows(isExpanded: isExpanded, depth: depth + 1)
        }
    }
}

#Preview {
    let vm = HistoryViewModel(repository: MockGitRepository())
    return ScrollView { LazyVStack(spacing: 0) { CommitTreeTab() } }
        .environment(vm)
        .frame(width: 480, height: 500)
        .panel()
        .padding()
        .background(Theme.background)
        .task {
            await vm.loadInitial()
            vm.selectDetailTab(.tree)
        }
}
