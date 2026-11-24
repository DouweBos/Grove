// Refs/RefOtherSections.swift
// GroveUIKit
//
// Remotes with their branches in folders, tags, other worktrees and submodules.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

struct RemotesSection: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.gitHost) private var uiHost
    let context: RefContext

    private var model: GitRefsModel { context.model }

    var body: some View {
        let remotes = model.refs.remotes
        if !remotes.isEmpty || model.refs.hasLoaded {
            Section(isExpanded: Binding(get: { model.isFiltering || model.isSectionExpanded(RefSection.remotes, default: true) },
                                        set: { model.setSection(RefSection.remotes, expanded: $0) })) {
                if remotes.isEmpty {
                    Button { context.present(.addRemote) } label: { GitSidebarRow(title: "Add Remote", symbol: "plus.circle") }
                        .buttonStyle(.plain)
                        .gitClickable()
                        .requires(.remotes)
                        .help("Connect this repository to a copy on GitHub or another server")
                }
                ForEach(remotes) { remote(remote: $0) }
            } header: {
                GitSectionLabel(title: "Remotes", count: remotes.count)
                    .contextMenu {
                        Button("Add Remote", systemImage: "plus") { context.present(.addRemote) }.requires(.remotes)
                    }
            }
        }
    }

    private func remote(remote: RemoteInfo) -> some View {
        let key = "remote/\(remote.name)"
        let all = model.remoteBranches(of: remote)
        return DisclosureGroup(isExpanded: Binding(get: { model.isFiltering || model.isExpanded(folder: key, containsHEAD: false) },
                                                   set: { model.setExpanded(folder: key, $0) })) {
            if model.isFiltering {
                LimitedRows(key: key, items: all.filter { model.matches($0.name) }, model: model) { remoteBranchRow($0) }
            } else {
                ForEach(model.remoteBranchGroups(of: remote), id: \.prefix) { group in
                    if let prefix = group.prefix {
                        RefFolder(key: "\(key)/\(prefix)", title: prefix, branches: group.branches, model: model) { remoteBranchRow($0) }
                    } else {
                        LimitedRows(key: key, items: group.branches, model: model) { remoteBranchRow($0) }
                    }
                }
            }
        } label: {
            GitSidebarRow(title: remote.name, symbol: "cloud", tint: style.info) {
                Text("\(all.count)").font(style.font(11, .regular, .monospaced))
            }
            .help(remote.url + (context.model.actions.commands.features.contains(.push) ? "\nDrop a local branch here to push it" : ""))
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.first else { return false }
                return model.handleDrop(payload, onRemote: remote)
            }
            .contextMenu { remoteMenu(remote) }
        }
    }

    @ViewBuilder
    private func remoteMenu(_ remote: RemoteInfo) -> some View {
        Button("Fetch \u{201C}\(remote.name)\u{201D}", systemImage: "arrow.down.circle") {
            Task { await model.run(.fetch(remote: remote.name)) }
        }
        Button("Prune Stale Branches", systemImage: "scissors") { Task { await model.run(.pruneRemote(remote.name)) } }
            .requires(.remotes)
        Divider()
        Button("Rename or Set URL", systemImage: "pencil") { context.present(.editRemote(remote)) }.requires(.remotes)
        Button("Copy URL", systemImage: "doc.on.doc") { uiHost.copy(remote.url) }
        Divider()
        Button("Add Remote", systemImage: "plus") { context.present(.addRemote) }.requires(.remotes)
        Button("Remove Remote", systemImage: "trash", role: .destructive) { model.confirmation = .removeRemote(remote) }
            .requires(.remotes)
    }

    private func remoteBranchRow(_ branch: BranchInfo) -> some View {
        let refs = model.refs
        let pullRequest = refs.pullRequest(for: branch)
        let ci = refs.ciStatus(for: branch)
        return GitSidebarRow(title: model.isFiltering ? branch.name : RefActionsViewModel.shortName(of: branch),
                             symbol: "arrow.triangle.branch", tint: style.info, detail: pullRequest?.label,
                             detailSymbol: pullRequest?.detailSymbol, detailTint: style.renamed,
                             isDimmed: pullRequest?.isMerged == true) {
            if let ci { BranchCIIcon(status: ci) }
        }
        .help(([branch.name] + [pullRequest?.tooltip, ci?.tooltip].compactMap { $0 }).joined(separator: "\n"))
        .accessibilityLabel(branch.name)
        .tag(GitRefItem.remoteBranch(branch.name))
        .draggable(branch.name)
        .contextMenu { RemoteBranchMenu(branch: branch, context: context) }
    }
}

/// Tags, closed by default since repositories often have thousands. Hidden when there are none.
struct TagsSection: View {
    @Environment(\.gitStyle) private var style
    let context: RefContext

    var body: some View {
        let model = context.model
        let tags = model.isFiltering ? model.refs.tags.filter { model.matches($0.name) } : model.refs.tags
        if !tags.isEmpty {
            Section(isExpanded: Binding(get: { model.isFiltering || model.tagsExpanded }, set: { model.tagsExpanded = $0 })) {
                LimitedRows(key: RefSection.tags, items: tags, model: model) { tag in
                    GitSidebarRow(title: tag.name, symbol: tag.isAnnotated ? "tag.fill" : "tag", tint: style.warning)
                        .accessibilityLabel(tag.name)
                        .tag(GitRefItem.tag(tag.name))
                        .draggable(tag.name)
                        .contextMenu { TagMenu(tag: tag, context: context) }
                }
            } header: {
                GitSectionLabel(title: "Tags", count: tags.count)
            }
        }
    }
}

/// The repository's other worktrees; from a linked worktree that includes the main one.
struct WorktreesSection: View {
    @Environment(\.gitStyle) private var style
    @Environment(\.gitFeatures) private var features
    @Environment(\.gitHost) private var uiHost
    let context: RefContext

    var body: some View {
        let model = context.model
        let worktrees = context.actions.otherWorktrees.filter { model.matches($0.branch ?? $0.folderName) }
        if !worktrees.isEmpty {
            Section(isExpanded: Binding(get: { model.isFiltering || model.isSectionExpanded(RefSection.worktrees, default: true) },
                                        set: { model.setSection(RefSection.worktrees, expanded: $0) })) {
                ForEach(worktrees) { row($0) }
            } header: {
                GitSectionLabel(title: "Worktrees", count: worktrees.count)
            }
        }
    }

    private func row(_ worktree: WorktreeInfo) -> some View {
        let host = context.host
        let pullRequest = worktree.branch.flatMap { context.model.refs.branchPullRequests[$0] }
        return GitSidebarRow(title: worktree.branch ?? "Detached HEAD",
                             symbol: worktree.isPrunable ? "questionmark.folder" : "tree",
                             tint: worktree.isPrunable ? style.warning : style.info,
                             detail: pullRequest.flatMap { $0.isMerged ? nil : $0.label }) {
            if worktree.isMain {
                Text("main").font(style.font(11, .medium))
            } else if worktree.isPrunable {
                Text("missing").font(style.font(11, .medium))
            } else if worktree.isLocked {
                Image(systemName: "lock.fill").font(style.font(10)).accessibilityLabel("Locked")
            }
        }
        .tag(GitRefItem.worktree(worktree.path))
        .help(worktree.isPrunable ? "\(abbreviatingHome(worktree.path)) no longer exists"
              : "\(abbreviatingHome(worktree.path)) · \(worktree.shortSHA)" + (host.openWorktree == nil ? "" : "\nDouble-click to open it"))
        .contextMenu {
            if let open = host.openWorktree {
                Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") { open(worktree) }.disabled(worktree.isPrunable)
            }
            if let switchTo = host.switchWorktree {
                Button("Switch to Worktree", systemImage: "tree") { switchTo(worktree) }.disabled(worktree.isPrunable)
            }
            if features.contains(.reveal) {
                Button("Reveal in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: worktree.path)])
                }
                .disabled(worktree.isPrunable)
            }
            Button("Copy Path", systemImage: "doc.on.doc") { uiHost.copy(worktree.path) }
            if !worktree.isMain {
                if worktree.isPrunable, let prune = host.pruneWorktrees {
                    Divider()
                    Button("Prune Missing Worktrees", systemImage: "scissors", action: prune)
                } else if !worktree.isPrunable, let remove = host.removeWorktree {
                    Divider()
                    Button("Remove Worktree", systemImage: "trash", role: .destructive) { remove(worktree) }
                        .disabled(worktree.isLocked)
                }
            }
        }
    }
}
#endif
