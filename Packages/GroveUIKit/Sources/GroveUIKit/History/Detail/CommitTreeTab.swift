// History/Detail/CommitTreeTab.swift
// GroveUIKit
//
// Every file in the repository as of the selected commit, with this commit's changes marked.

#if os(macOS)
import GroveKit
import SwiftUI

struct CommitTreeTab<Menu: View>: View {
    @Environment(\.gitStyle) private var style
    let viewModel: HistoryViewModel
    @ViewBuilder let menu: (String) -> Menu
    /// Folders flipped away from the default, which opens only those with changes.
    @State private var toggled: Set<String> = []
    @State private var cache = TreeCache()

    var body: some View {
        if viewModel.isLoadingTree && viewModel.treeFiles.isEmpty {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(GitMetrics.Spacing.xl)
        } else {
            let built = cache.tree(viewModel.treeFiles, changes: viewModel.commitDiffs)
            HStack {
                GitSectionLabel(title: "\(viewModel.treeFiles.count) file\(viewModel.treeFiles.count == 1 ? "" : "s")")
                Text("\(built.changed.count) changed").font(style.monoCaption).foregroundStyle(style.textSecondary)
            }
            .padding(.horizontal, GitMetrics.Spacing.lg)
            .padding(.top, GitMetrics.Spacing.md)
            .padding(.bottom, GitMetrics.Spacing.xs)
            let isExpanded = { (path: String) in built.changedFolders.contains(path) != toggled.contains(path) }
            ForEach(built.tree.visibleRows(isExpanded: isExpanded)) { row in
                treeRow(row, status: built.changed[row.path], isExpanded: row.isDirectory && isExpanded(row.path))
            }
        }
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
                        .font(style.font(9, .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 10 * style.fontScale)
                        .foregroundStyle(style.textSecondary)
                }
                Image(systemName: row.isDirectory ? "folder.fill" : "doc")
                    .font(style.font(12))
                    .foregroundStyle(row.isDirectory ? style.info : style.textSecondary)
                    .frame(width: 16 * style.fontScale)
                Text(row.name)
                    .font(style.font(13, status == nil ? .regular : .medium))
                    .foregroundStyle(style.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: GitMetrics.Spacing.sm)
                if let status { CommitFileStatusBadge(status: status) }
            }
            .padding(.leading, (GitMetrics.Spacing.lg + CGFloat(row.depth) * 16 + (row.isDirectory ? 0 : 16)) * style.fontScale)
            .padding(.trailing, GitMetrics.Spacing.lg)
            .frame(height: 26 * style.fontScale)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gitClickable(row.isDirectory || status != nil)
        .contextMenu { if !row.isDirectory { menu(row.path) } }
    }
}

/// The tree built once per commit rather than per render; a big repository has tens of thousands of files.
@MainActor
final class TreeCache {
    struct Built {
        let tree: FileTreeNode
        let changed: [String: FileStatus]
        let changedFolders: Set<String>
    }

    private var key: [AnyHashable] = []
    private var built: Built?

    func tree(_ files: [String], changes: [FileDiff]) -> Built {
        let key: [AnyHashable] = [files.count, files.first, files.last, changes.count, changes.first?.path]
        if let built, key == self.key { return built }
        let changed = Dictionary(changes.map { ($0.path, $0.status) }, uniquingKeysWith: { first, _ in first })
        let next = Built(tree: FileTreeNode.build(from: files), changed: changed,
                         changedFolders: Self.ancestorFolders(of: changed.keys))
        self.key = key
        built = next
        return next
    }

    static func ancestorFolders(of paths: some Sequence<String>) -> Set<String> {
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
#endif
