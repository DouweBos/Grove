// Views/Sidebar/SidebarViewModel+Refs.swift
// Grove
//
// What Grove brings to GroveUIKit's refs sidebar: pins and archives, worktrees, pull requests, runs, history,
// flow branches, and moving a stack by dropping it on a branch.

import AppKit
import GroveKit
import GroveUIKit
import SwiftUI
import UniformTypeIdentifiers

extension SidebarViewModel {

    /// Everything but opening submodules, which needs the window's environment.
    var refsHost: GitRefsHost {
        var host = GitRefsHost()
        host.marks = branchMarks
        host.setPinned = { [weak self] in self?.setPinned($0, $1) }
        host.setArchived = { [weak self] in self?.setArchived($0, $1) }
        host.hiddenBranches = stackedBranchNames
        host.openWorktree = { [weak self] in self?.openInNewTab($0) }
        host.switchWorktree = { [weak self] in self?.switchTo($0) }
        host.removeWorktree = { [weak self] in self?.requestRemoval(of: $0) }
        host.pruneWorktrees = { [actions] in Task { await actions.pruneWorktrees() } }
        host.addSubmodule = { [weak self] in self?.requestAddSubmodule() }
        host.createPullRequest = { [weak self] in self?.onCreatePullRequest?($0) }
        host.showRuns = { [weak self] in self?.onShowRuns?($0) }
        host.revealInHistory = { [weak self] sha, item in
            guard let self, let item = sidebarItem(for: item) else { return }
            onRevealInHistory?(sha, item)
        }
        host.exportFiles = { [weak self] ref in
            Task {
                guard let self, let url = await SavePanel.choose(
                    name: self.archiveFileName(for: ref), message: "Export the files of \u{201C}\(ref)\u{201D} as a ZIP archive",
                    prompt: "Export", type: .zip) else { return }
                await self.exportFiles(of: ref, to: url)
            }
        }
        host.branchMenu = { [weak self] branch in
            guard let gitFlow = self?.gitFlow, let flow = gitFlow.config?.classify(branch: branch.name) else { return AnyView(EmptyView()) }
            return AnyView(Button("Finish \(flow.kind.title) \u{201C}\(flow.name)\u{201D}", systemImage: flow.kind.symbol) {
                gitFlow.present(.finish(flow.kind, name: flow.name))
            })
        }
        host.drop = { [weak self] payload, target, option in self?.stackDrop(payload, onto: target, option: option) }
        return host
    }

    /// The sidebar's selection as GroveUIKit's, and back.
    var refSelection: GitRefItem? {
        switch selection {
        case .branch(let branch): .branch(branch.name)
        case .remoteBranch(let branch): .remoteBranch(branch.name)
        case .tag(let tag): .tag(tag.name)
        case .branchStack(let id): .host(Self.stackTag + id)
        default: nil
        }
    }

    func select(ref item: GitRefItem?) {
        guard let item, let selected = sidebarItem(for: item) else { return }
        select(selected)
    }

    static let stackTag = "stack:"

    private func sidebarItem(for item: GitRefItem) -> SidebarItem? {
        switch item {
        case .branch(let name): localBranches.first { $0.name == name }.map(SidebarItem.branch)
        case .remoteBranch(let name): remoteBranches.first { $0.name == name }.map(SidebarItem.remoteBranch)
        case .tag(let name): tags.first { $0.name == name }.map(SidebarItem.tag)
        case .host(let id) where id.hasPrefix(Self.stackTag): .branchStack(String(id.dropFirst(Self.stackTag.count)))
        default: nil
        }
    }

    /// A stacked branch dropped on another branch moves it and everything on it; Option leaves it to a plain rebase.
    private func stackDrop(_ payload: String, onto target: BranchInfo, option: Bool) -> GitRefCustomDrop? {
        guard !option, let stack = refs.stack(containing: payload) else { return nil }
        let headName = localBranches.first(where: \.isHEAD)?.name
        let repository = repository
        return GitRefCustomDrop(
            id: "move-\(payload)-\(target.name)", title: "Move \(payload) onto \(target.name)?",
            message: "Rebases \(payload)'s own commits onto \(target.name), then restacks every branch built on it.",
            symbol: "square.stack.3d.up", primaryTitle: "Move", fields: [("Move", payload), ("Onto", target.name)]
        ) { [weak self] in
            let plan = RestackPlan.make(stack, mode: .move(payload, onto: target.name), trunkRef: stack.trunk, headBranch: headName)
            do {
                try await repository.restack(plan)
            } catch RestackError.stopped {
                self?.select(.workingCopy)
            }
        }
    }
}
