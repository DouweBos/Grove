// RefsSidebarTests.swift
// GroveUIKitTests
//
// The refs sidebar's grouping, marks, filter, folders and drops, and the sidebar, stashes, reflog and review laying out.

#if os(macOS)
import AppKit
@testable import GroveKit
import SwiftUI
import Testing
@testable import GroveUIKit

@MainActor
private final class RefsSpyCommands: GitCommandPerforming {
    let features: GitFeatures
    private(set) var performed: [GitCommand] = []

    init(features: GitFeatures = .all) { self.features = features }

    func perform(_ command: GitCommand, progress: (@Sendable (Double) -> Void)?) async throws {
        try requireSupport(for: command)
        performed.append(command)
    }
}

private func branch(_ name: String, remote: Bool = false, head: Bool = false) -> BranchInfo {
    BranchInfo(id: (remote ? "refs/remotes/" : "refs/heads/") + name, name: name, isLocal: !remote, isRemote: remote, isHEAD: head,
               targetSHA: "s", remoteName: remote ? "origin" : nil, upstream: nil, ahead: 0, behind: 0)
}

@MainActor
@Suite(.serialized)
struct RefsSidebarTests {

    private func model(_ commands: RefsSpyCommands? = nil) -> GitRefsModel {
        let repository = MockGitRepository()
        let actions = RefActionsViewModel(repository: repository, refs: RepositoryRefs(repository: repository))
        if let commands {
            actions.commands = commands
            actions.onRepositoryChanged = {}
        }
        return GitRefsModel(actions: actions)
    }

    @Test func localBranchGroups_includesAllLocalBranches() async {
        let vm = model()
        await vm.refs.refresh()

        let allGroupedBranches = vm.localBranchGroups().flatMap(\.branches)
        #expect(allGroupedBranches.count == vm.refs.localBranches.count,
                "localBranchGroups should contain all local branches, not just active ones")
    }

    @Test func remoteBranchGroups_foldersByPrefixWithoutTheRemote() {
        let vm = model()
        let remote = RemoteInfo(id: "origin", name: "origin", url: "git@example.com:a/b.git")
        let branches = ["origin/HEAD", "origin/main", "origin/adam/ima", "origin/adam/mat", "origin/alex/oom"].map { branch($0, remote: true) }
        vm.refs.replace(remoteBranches: branches, remotes: [remote])

        let groups = vm.remoteBranchGroups(of: remote)
        #expect(groups.map(\.prefix) == [nil, "adam", "alex"])
        #expect(groups.map { $0.branches.map(\.name) } == [["origin/main"], ["origin/adam/ima", "origin/adam/mat"], ["origin/alex/oom"]])
    }

    @Test func localBranchGroups_listTheTrunkFirst() {
        let vm = model()
        vm.refs.replace(localBranches: ["code-editor-plan", "main", "zeta"].map { branch($0) }, stacks: [MockData.linearStack])

        #expect(vm.localBranchGroups().first?.branches.map(\.name) == ["main", "code-editor-plan", "zeta"])
    }

    @Test func folderOpenedForHEADClosesWhenHEADLeaves() {
        var expansion = GitFolderExpansion(containsHEAD: true)
        expansion.headChanged(contains: false)
        #expect(!expansion.isExpanded)
        expansion.headChanged(contains: true)
        #expect(expansion.isExpanded)
    }

    @Test func folderTheUserToggledStaysAsLeft() {
        var opened = GitFolderExpansion(containsHEAD: false)
        opened.toggle(to: true)
        opened.headChanged(contains: true)
        opened.headChanged(contains: false)
        #expect(opened.isExpanded)

        var closed = GitFolderExpansion(containsHEAD: true)
        closed.toggle(to: false)
        closed.headChanged(contains: false)
        closed.toggle(to: true)
        closed.headChanged(contains: false)
        #expect(closed.isExpanded)
        #expect(!GitFolderExpansion(containsHEAD: false).isExpanded)
    }

    @Test func marksLeadHideAndArchiveBranches() {
        let vm = model()
        vm.refs.replace(localBranches: ["main", "base", "zeta", "feature/a", "old", "layer"].map { branch($0, head: $0 == "zeta") })
        let marks = GitBranchMarks(pinned: ["feature/a"], archived: ["old", "gone"], protected: ["main"], base: "base")

        let groups = vm.localBranchGroups(marks, hiding: ["layer"])
        #expect(groups.map(\.prefix) == [nil, "feature"])
        #expect(groups[0].branches.map(\.name) == ["base", "zeta"])
        #expect(vm.protectedBranches(marks).map(\.name) == ["main"])
        #expect(vm.pinnedBranches(marks).map(\.name) == ["feature/a"])
        #expect(vm.archivedBranches(marks).map(\.name) == ["gone", "old"])
        #expect(vm.archivedBranches(marks).map { $0.branch == nil } == [true, false])
        #expect(vm.listedBranchCount(marks) == 5)
    }

    @Test func theFilterMatchesAnyPartOfAName() {
        let vm = model()
        #expect(!vm.isFiltering && vm.matches("anything"))
        vm.filter = "  TEAM1/f "
        #expect(vm.isFiltering)
        #expect(vm.matches("team1/feature-7") && vm.matches("origin/team1/feature-7"))
        #expect(!vm.matches("team2/feature-7"))
    }

    @Test func dropsOnlyOfferWhatTheRepositorySupports() {
        var features = GitFeatures.all
        features.remove([.merge, .checkout, .push, .editBranches], reason: "Not here")
        let vm = model(RefsSpyCommands(features: features))
        vm.refs.replace(localBranches: [branch("main", head: true), branch("topic"), branch("other")],
                        remoteBranches: [branch("origin/main", remote: true)],
                        remotes: [RemoteInfo(id: "origin", name: "origin", url: "/tmp/o")])
        let main = vm.refs.localBranches[0]
        let topic = vm.refs.localBranches[1]

        #expect(!vm.handleDrop("topic", onBranch: main, option: false))
        #expect(vm.handleDrop("topic", onBranch: main, option: true))
        #expect(!vm.handleDrop("other", onBranch: topic, option: true), "Rebasing a branch that isn't HEAD checks it out first")
        #expect(vm.handleDrop("origin/main", onBranch: main, option: false))
        #expect(!vm.handleDrop("origin/main", onBranch: topic, option: false), "Fast-forwarding another branch edits it")
        #expect(!vm.handleDrop("topic", onRemote: RemoteInfo(id: "origin", name: "origin", url: "/tmp/o")))
    }

    @Test func dropsRunThroughTheCommands() async {
        let spy = RefsSpyCommands()
        let vm = model(spy)
        vm.refs.replace(localBranches: [branch("main", head: true), branch("topic")],
                        remoteBranches: [branch("origin/main", remote: true)])

        vm.requestDrop(.merge(source: "main", target: "topic"))
        await vm.confirmDrop()
        vm.requestDrop(.pull(remoteBranch: "origin/main", target: "topic"))
        await vm.confirmDrop()
        vm.requestDrop(.pull(remoteBranch: "origin/main", target: "main"))
        await vm.confirmDrop(pullStrategy: .rebase)
        vm.requestDrop(.push(branch: "topic", remote: "origin"))
        await vm.confirmDrop(remoteBranchName: " review/topic ", setUpstream: true)
        var ran = false
        vm.requestDrop(.custom(GitRefCustomDrop(id: "stack", title: "Move", message: "", symbol: "square", primaryTitle: "Move",
                                                fields: [], run: { ran = true })))
        await vm.confirmDrop()

        #expect(spy.performed == [
            .checkout("topic"), .merge("main", squash: false),
            .fastForward(branch: "topic", remote: "origin", remoteBranch: "main"),
            .pull(remote: "origin", branch: "main", strategy: .rebase, options: PullOptions()),
            .pushBranch("topic", remote: "origin", as: "review/topic", forceWithLease: false, setUpstream: true, options: PushOptions()),
        ])
        #expect(ran && vm.pendingDrop == nil)
    }

    @Test func anAppsDropTakesPrecedence() {
        let vm = model()
        vm.refs.replace(localBranches: [branch("main", head: true), branch("layer")])
        var host = GitRefsHost()
        host.drop = { payload, target, _ in
            GitRefCustomDrop(id: payload, title: "Move \(payload) onto \(target.name)?", message: "", symbol: "square",
                             primaryTitle: "Move", fields: []) {}
        }
        #expect(vm.handleDrop("layer", onBranch: vm.refs.localBranches[0], option: false, host: host))
        if case .custom(let drop) = vm.pendingDrop { #expect(drop.title == "Move layer onto main?") } else { Issue.record("no drop") }
    }

    @Test func aBlockedCheckoutOffersToStashOrDiscard() async {
        let vm = model(RefsSpyCommands())
        await vm.checkout("topic", carrying: .stash)
        #expect(vm.blockedCheckout == nil)
        #expect((vm.actions.commands as? RefsSpyCommands)?.performed == [.stashAndCheckout("topic")])
    }

    @Test func longListsShowMoreInPages() {
        let vm = model()
        #expect(vm.limit("tags") == GitRefsModel.pageSize)
        vm.showMore("tags")
        #expect(vm.limit("tags") == GitRefsModel.pageSize * 5)
        vm.setSection(RefSection.tags, expanded: true)
        #expect(vm.tagsExpanded)
    }

    // MARK: Views

    private func render(_ view: some View, width: CGFloat, height: CGFloat = 700) -> (NSWindow, NSHostingView<AnyView>) {
        let hosting = NSHostingView(rootView: AnyView(view.frame(width: width, height: height)))
        let window = NSWindow(contentRect: NSRect(x: -9000, y: -9000, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return (window, hosting)
    }

    @Test func theSidebarLaysOutEverySectionFilteredZoomedAndWithoutFeatures() async {
        let vm = model()
        await vm.refs.refresh()
        var host = GitRefsHost()
        host.marks = GitBranchMarks(pinned: ["develop"], archived: ["gone"], protected: ["main"])
        host.setPinned = { _, _ in }
        let context = GitDialogContext(repository: vm.actions.repository, refs: vm.refs, commands: vm.actions.commands)
        var worktreeSession = GitFeatures.all
        worktreeSession.remove([.checkout, .createBranch, .editBranches, .remotes, .tag], reason: "Only in the project root")
        for (scale, features, filter) in [(1.0, GitFeatures.all, ""), (1.3, worktreeSession, ""), (1.0, .all, "feature")] {
            vm.filter = filter
            vm.tagsExpanded = true
            var style = GitUIStyle.system
            style.fontScale = scale
            let (window, hosting) = render(
                GitRefsSidebar(model: vm, dialogs: context, selection: .constant(.branch("main")), host: host)
                    .gitUIStyle(style).gitFeatures(features), width: 280)
            #expect(hosting.fittingSize.width > 0)
            window.orderOut(nil)
        }
    }

    @Test func stashesReflogAndReviewLayOut() async {
        let repository = MockGitRepository()
        let refs = RepositoryRefs(repository: repository)
        let context = GitDialogContext(repository: repository, refs: refs, commands: RepositoryCommands(repository: repository))
        let stashes = StashesViewModel(repository: repository)
        await stashes.refresh()
        if let first = stashes.stashes.first { await stashes.select(first) }
        let reflog = ReflogViewModel(repository: repository)
        await reflog.refresh()
        if let first = reflog.entries.first { await reflog.select(first) }
        let review = BranchesReviewViewModel(repository: repository, refs: refs)
        await review.refresh()
        var noBranches = GitFeatures.all
        noBranches.remove([.editBranches, .createBranch], reason: "Only in the project root")
        for width in [1180.0, 640] {
            for view in [AnyView(GitStashesView(viewModel: stashes, dialogs: context)),
                         AnyView(GitReflogView(viewModel: reflog, dialogs: context)),
                         AnyView(GitBranchesReviewView(viewModel: review).gitFeatures(noBranches))] {
                let (window, hosting) = render(view, width: width)
                #expect(hosting.fittingSize.width > 0)
                window.orderOut(nil)
            }
        }
        #expect(!stashes.stashes.isEmpty && !reflog.entries.isEmpty && !review.branches.isEmpty)
    }
}
#endif
