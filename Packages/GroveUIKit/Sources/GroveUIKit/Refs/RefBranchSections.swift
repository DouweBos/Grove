// Refs/RefBranchSections.swift
// GroveUIKit
//
// Local branches: protected and pinned first, then flat names, the app's rows, then "prefix/" folders; and Archived.
// Rows are draggable; dropping a ref on the header starts a new branch from it.

#if os(macOS)
import GroveKit
import SwiftUI

struct BranchesSection<Extra: View>: View {
    @Environment(\.gitFeatures) private var features
    let context: RefContext
    let extra: () -> Extra

    private var model: GitRefsModel { context.model }
    private var marks: GitBranchMarks { context.host.marks }

    var body: some View {
        Section {
            if model.isFiltering {
                let matches = model.refs.localBranchesMatchingStacks.filter { !marks.archived.contains($0.name) && model.matches($0.name) }
                LimitedRows(key: "branches", items: matches, model: model) { branchRow($0, fullName: true) }
            } else {
                ForEach(model.protectedBranches(marks)) { branchRow($0, fullName: true) }
                ForEach(model.pinnedBranches(marks)) { branchRow($0, fullName: true) }
                ForEach(model.localBranchGroups(marks, hiding: context.host.hiddenBranches), id: \.prefix) { group in
                    if let prefix = group.prefix {
                        RefFolder(key: "local/\(prefix)", title: prefix, branches: group.branches, model: model) {
                            branchRow($0, fullName: false)
                        }
                    } else {
                        ForEach(group.branches) { branchRow($0, fullName: true) }
                        extra()
                    }
                }
            }
        } header: {
            GitSectionLabel(title: "Branches", count: model.listedBranchCount(marks))
                .dropDestination(for: String.self) { items, _ in
                    guard let ref = items.first, !ref.isEmpty, features.contains(.createBranch) else { return false }
                    context.present(.createBranch(from: ref))
                    return true
                }
                .contextMenu {
                    Button("New Branch", systemImage: "plus") { context.present(.createBranch()) }
                        .requires(.createBranch)
                }
        }
    }

    private func branchRow(_ branch: BranchInfo, fullName: Bool) -> some View {
        RefBranchRow(branch: branch, fullName: fullName, context: context)
            .branchActions(branch, context: context)
    }
}

/// A local branch: name, pin, lock, CI and ahead/behind.
struct RefBranchRow: View {
    @Environment(\.gitStyle) private var style
    let branch: BranchInfo
    /// The whole name, else the part after a folder's "prefix/".
    var fullName = true
    let context: RefContext

    private var title: String {
        guard !fullName, let slash = branch.name.firstIndex(of: "/") else { return branch.name }
        return String(branch.name[branch.name.index(after: slash)...])
    }

    var body: some View {
        let marks = context.host.marks
        let refs = context.model.refs
        let pullRequest = refs.pullRequest(for: branch)
        let worktree = context.actions.worktree(checkingOut: branch)
        GitSidebarRow(title: title, symbol: branch.isHEAD ? "checkmark.circle.fill" : "arrow.triangle.branch",
                      tint: branch.isHEAD ? style.accent : nil, detail: pullRequest?.label,
                      detailSymbol: pullRequest?.detailSymbol, detailTint: style.renamed, isEmphasized: branch.isHEAD,
                      isDimmed: pullRequest?.isMerged == true, badgeSymbol: worktree == nil ? nil : "tree.circle.fill") {
            HStack(spacing: GitMetrics.Spacing.xs) {
                if let ci = refs.ciStatus(for: branch) { BranchCIIcon(status: ci) }
                if marks.pinned.contains(branch.name) {
                    Image(systemName: "pin.fill").font(style.font(9)).rotationEffect(.degrees(45)).accessibilityLabel("Pinned")
                }
                if marks.protected.contains(branch.name) {
                    Image(systemName: "lock.fill").font(style.font(9)).help("Protected branch").accessibilityLabel("Protected")
                }
                GitAheadBehind(ahead: branch.ahead, behind: branch.behind)
            }
        }
        .help(tooltip(pullRequest: pullRequest, worktree: worktree))
        .accessibilityLabel(branch.name)
    }

    private func tooltip(pullRequest: BranchPullRequest?, worktree: WorktreeInfo?) -> String {
        var text = branch.upstreamShortName.map { "\(branch.name) → \($0)" } ?? branch.name
        if let parent = context.model.refs.parents[branch.name] { text += "\nParent: \(parent)" }
        if let pullRequest { text += "\n" + pullRequest.tooltip }
        if let ci = context.model.refs.ciStatus(for: branch) { text += "\n" + ci.tooltip }
        guard let worktree else { return text }
        let place = worktree.isMain ? "the main worktree" : "worktree \(worktree.folderName)"
        return "\(text)\nChecked out in \(place)." + (context.host.openWorktree == nil ? "" : " Double-click to open it.")
    }
}

extension View {
    /// Selection, drag and drop and the menu, the same for every local branch row.
    func branchActions(_ branch: BranchInfo, context: RefContext, menuLeading: AnyView? = nil) -> some View {
        tag(GitRefItem.branch(branch.name))
            .draggable(branch.name)
            // Another branch dropped here merges into this one (Option rebases this one onto it); a remote branch pulls.
            .dropDestination(for: String.self) { items, _ in
                guard let payload = items.first else { return false }
                return context.model.handleDrop(payload, onBranch: branch, option: NSEvent.modifierFlags.contains(.option),
                                                host: context.host)
            }
            .contextMenu {
                if let menuLeading {
                    menuLeading
                    Divider()
                }
                BranchMenu(branch: branch, context: context)
            }
    }
}

/// A "prefix/" folder of branches; it opens when it holds the checked-out branch, so HEAD is always in sight.
struct RefFolder<Row: View>: View {
    @Environment(\.gitStyle) private var style
    let key: String
    let title: String
    let branches: [BranchInfo]
    let model: GitRefsModel
    @ViewBuilder let row: (BranchInfo) -> Row

    var body: some View {
        let containsHEAD = branches.contains(where: \.isHEAD)
        DisclosureGroup(isExpanded: Binding(get: { model.isExpanded(folder: key, containsHEAD: containsHEAD) },
                                            set: { model.setExpanded(folder: key, $0) })) {
            LimitedRows(key: key, items: branches, model: model, row: row)
        } label: {
            GitSidebarRow(title: title, symbol: "folder") {
                Text("\(branches.count)").font(style.font(11, .regular, .monospaced))
            }
        }
        .onChange(of: containsHEAD) { _, contains in model.headChanged(folder: key, contains: contains) }
    }
}

/// Up to the model's limit of rows, then Show More.
struct LimitedRows<Item: Identifiable, Row: View>: View {
    @Environment(\.gitStyle) private var style
    let key: String
    let items: [Item]
    let model: GitRefsModel
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        let limit = model.limit(key)
        ForEach(items.prefix(limit)) { row($0) }
        if items.count > limit {
            Button { model.showMore(key) } label: {
                GitSidebarRow(title: "Show More", symbol: "ellipsis.circle") {
                    Text("\(items.count - limit)").font(style.font(11, .regular, .monospaced))
                }
            }
            .buttonStyle(.plain)
            .gitClickable()
            .selectionDisabled()
        }
    }
}

/// Branches the app archived: hidden from Branches, also listed when gone so they can be unarchived.
struct ArchivedSection: View {
    @Environment(\.gitStyle) private var style
    let context: RefContext

    var body: some View {
        let model = context.model
        let archived = model.archivedBranches(context.host.marks).filter { model.matches($0.name) }
        if !archived.isEmpty {
            Section(isExpanded: Binding(get: { model.isFiltering || model.isSectionExpanded(RefSection.archived, default: false) },
                                        set: { model.setSection(RefSection.archived, expanded: $0) })) {
                ForEach(archived, id: \.name) { entry in
                    if let branch = entry.branch {
                        RefBranchRow(branch: branch, context: context)
                            .tag(GitRefItem.branch(branch.name))
                            .draggable(branch.name)
                            .contextMenu { menu(entry.name, branch: branch) }
                    } else {
                        GitSidebarRow(title: entry.name, symbol: "archivebox", isDimmed: true)
                            .help("\(entry.name) no longer exists")
                            .selectionDisabled()
                            .contextMenu { menu(entry.name, branch: nil) }
                    }
                }
            } header: {
                GitSectionLabel(title: "Archived", count: archived.count)
            }
        }
    }

    @ViewBuilder
    private func menu(_ name: String, branch: BranchInfo?) -> some View {
        if let setArchived = context.host.setArchived {
            Button("Unarchive", systemImage: "tray.and.arrow.up") { setArchived(name, false) }
        }
        Button("Check Out \u{201C}\(name)\u{201D}", systemImage: "arrow.uturn.backward") {
            Task { await context.model.checkout(name) }
        }
        .disabled(branch == nil || branch?.isHEAD == true)
        .requires(.checkout)
        if let branch {
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { context.present(.deleteBranch(branch)) }
                .disabled(branch.isHEAD)
                .requires(.editBranches)
        }
    }
}
#endif
