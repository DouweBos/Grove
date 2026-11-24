// Refs/RefMenus.swift
// GroveUIKit
//
// The context menus of branches, remote branches and tags. Each item checks its feature; the app's leave out when nil.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI

/// What every row reaches: the model, the app's part and the dialogs.
struct RefContext {
    let model: GitRefsModel
    let host: GitRefsHost
    let present: (GitDialog) -> Void

    var actions: RefActionsViewModel { model.actions }
    var currentName: String { model.headName ?? "HEAD" }
}

/// Everything a local branch offers.
struct BranchMenu: View {
    @Environment(\.gitHost) private var uiHost
    let branch: BranchInfo
    let context: RefContext

    var body: some View {
        let host = context.host
        let name = branch.name
        let current = context.currentName
        let worktree = context.actions.worktree(checkingOut: branch)
        if let extra = host.branchMenu?(branch) {
            extra
            Divider()
        }
        if let worktree, host.openWorktree != nil || host.switchWorktree != nil {
            if let open = host.openWorktree {
                Button("Open Worktree in New Tab", systemImage: "plus.rectangle.on.rectangle") { open(worktree) }
            }
            if let switchTo = host.switchWorktree {
                Button("Switch to Worktree", systemImage: "tree") { switchTo(worktree) }
            }
        } else {
            Button("Check Out \u{201C}\(name)\u{201D}", systemImage: "arrow.uturn.backward") {
                Task { await context.model.checkout(name) }
            }
            .disabled(branch.isHEAD || worktree != nil)
            .requires(.checkout)
        }
        Button("New Branch from \u{201C}\(name)\u{201D}", systemImage: "arrow.triangle.branch") {
            context.present(.createBranch(from: name))
        }
        .requires(.createBranch)
        RefShareItems(ref: name, branch: branch, item: .branch(name), sha: branch.targetSHA, context: context)
        Divider()
        Button("Merge into \u{201C}\(current)\u{201D}", systemImage: "arrow.triangle.merge") {
            Task { await context.actions.merge(branch: branch) }
        }
        .disabled(branch.isHEAD)
        .requires(.merge)
        Button("Squash-Merge into \u{201C}\(current)\u{201D}", systemImage: "square.stack") {
            Task { await context.model.run(.merge(name, squash: true)) }
        }
        .disabled(branch.isHEAD)
        .requires(.merge)
        Button("Rebase \u{201C}\(current)\u{201D} onto This", systemImage: "arrow.triangle.pull") {
            Task { await context.actions.rebase(onto: branch) }
        }
        .disabled(branch.isHEAD)
        .requires(.rebase)
        Divider()
        Button(branch.upstream == nil ? "Publish" : "Push", systemImage: "arrow.up.to.line") {
            context.present(.push(branch: name))
        }
        .requires(.push)
        if branch.isHEAD {
            Button("Pull", systemImage: "arrow.down.to.line") { context.present(.pull) }
        }
        Divider()
        Button("Rename", systemImage: "pencil") { context.present(.renameBranch(name)) }
            .requires(.editBranches)
        Button(branch.upstream == nil ? "Track Remote Branch" : "Change Tracked Branch", systemImage: "arrow.left.arrow.right") {
            context.present(.trackRemoteBranch(branch))
        }
        .disabled(context.actions.trackableRemoteBranches.isEmpty)
        .requires(.editBranches)
        if let upstream = branch.upstreamShortName {
            Button("Stop Tracking \u{201C}\(upstream)\u{201D}", systemImage: "xmark.circle") {
                Task { await context.actions.stopTracking(branch) }
            }
            .requires(.editBranches)
        }
        if let setPinned = host.setPinned {
            let pinned = host.marks.pinned.contains(name)
            Button(pinned ? "Unpin" : "Pin to Top", systemImage: pinned ? "pin.slash" : "pin") { setPinned(name, !pinned) }
        }
        if let setArchived = host.setArchived {
            Button("Archive", systemImage: "archivebox") { setArchived(name, true) }
                .disabled(branch.isHEAD || worktree != nil)
        }
        Button("Copy Name", systemImage: "doc.on.doc") { uiHost.copy(name) }
        Divider()
        // The dialog offers to remove the worktree first.
        Button("Delete", systemImage: "trash", role: .destructive) { context.present(.deleteBranch(branch)) }
            .disabled(branch.isHEAD)
            .requires(.editBranches)
    }
}

/// A remote-tracking branch's menu.
struct RemoteBranchMenu: View {
    @Environment(\.gitHost) private var uiHost
    let branch: BranchInfo
    let context: RefContext

    var body: some View {
        let short = RefActionsViewModel.shortName(of: branch)
        let hasLocal = context.model.refs.localBranches.contains { $0.name == short }
        Button(hasLocal ? "Check Out \u{201C}\(short)\u{201D}" : "Check Out as Tracking Branch", systemImage: "arrow.uturn.backward") {
            Task { await context.model.checkout(short) }
        }
        .requires(.checkout)
        Button("New Branch from \u{201C}\(branch.name)\u{201D}", systemImage: "arrow.triangle.branch") {
            context.present(.createBranch(from: branch.name))
        }
        .requires(.createBranch)
        Button("Merge into \u{201C}\(context.currentName)\u{201D}", systemImage: "arrow.triangle.merge") {
            Task { await context.actions.merge(branch: branch) }
        }
        .requires(.merge)
        RefShareItems(ref: branch.name, branch: branch, item: .remoteBranch(branch.name), sha: branch.targetSHA, context: context)
        Button("Copy Name", systemImage: "doc.on.doc") { uiHost.copy(branch.name) }
        Divider()
        Button("Delete on Remote", systemImage: "trash", role: .destructive) {
            context.model.confirmation = .deleteRemoteBranch(branch)
        }
        .requires(.editBranches)
        .requires(.push)
    }
}

/// A tag's menu.
struct TagMenu: View {
    @Environment(\.gitHost) private var uiHost
    let tag: TagInfo
    let context: RefContext

    var body: some View {
        let remote = context.model.refs.remotes.first?.name
        Button("Check Out \u{201C}\(tag.name)\u{201D}", systemImage: "arrow.uturn.backward") {
            Task { await context.model.checkout(tag.name) }
        }
        .requires(.checkout)
        Button("New Branch from \u{201C}\(tag.name)\u{201D}", systemImage: "arrow.triangle.branch") {
            context.present(.createBranch(from: tag.name))
        }
        .requires(.createBranch)
        RefShareItems(ref: tag.name, branch: nil, item: .tag(tag.name), sha: tag.targetSHA, context: context)
        Button("Push to \(remote ?? "Remote")", systemImage: "arrow.up.to.line") {
            Task { await context.model.run(.pushTag(tag.name, remote: remote)) }
        }
        .disabled(remote == nil)
        .requires(.push)
        .requires(.tag)
        Button("Copy Name", systemImage: "doc.on.doc") { uiHost.copy(tag.name) }
        Divider()
        Button("Delete Tag", systemImage: "trash", role: .destructive) { context.model.confirmation = .deleteTag(tag) }
            .requires(.tag)
    }
}

/// Pull requests, runs, history, export and compare for any ref, as far as the app offers them.
private struct RefShareItems: View {
    let ref: String
    let branch: BranchInfo?
    let item: GitRefItem
    let sha: String
    let context: RefContext

    var body: some View {
        let host = context.host
        let pullRequest = branch.flatMap { context.model.refs.pullRequest(for: $0) }
        let remoteName = branch.map { $0.isRemote ? RefActionsViewModel.shortName(of: $0) : $0.name }
        if let pullRequest, let url = URL(string: pullRequest.url) {
            Button("Open Pull Request \(pullRequest.label) in Browser", systemImage: "arrow.triangle.pull") {
                NSWorkspace.shared.open(url)
            }
        } else if let create = host.createPullRequest, let remoteName {
            Button("Create Pull Request", systemImage: "arrow.triangle.pull") { create(remoteName) }
        }
        if let showRuns = host.showRuns, let remoteName {
            Button("Show Runs for Branch", systemImage: "play.circle") { showRuns(remoteName) }
        }
        if let reveal = host.revealInHistory {
            Button("Reveal in History", systemImage: "clock.arrow.circlepath") { reveal(sha, item) }
        }
        if let export = host.exportFiles {
            Button("Export Files", systemImage: "square.and.arrow.up") { export(ref) }
                .requires(.export)
        }
        if let compare = host.compare, branch?.isHEAD != true {
            Button("Compare with \u{201C}\(context.currentName)\u{201D}", systemImage: "arrow.left.arrow.right.square") {
                compare(context.currentName, ref)
            }
        }
    }
}
#endif
