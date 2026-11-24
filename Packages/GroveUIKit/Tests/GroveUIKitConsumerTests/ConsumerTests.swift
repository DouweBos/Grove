// ConsumerTests.swift
// GroveUIKitConsumerTests
//
// Built in Swift 6 without Grove's default isolation, as an importing app is.

#if os(macOS)
import GroveKit
import GroveUIKit
import SwiftUI
import Testing

@MainActor
private final class HostCommands: GitCommandPerforming {
    let features: GitFeatures
    private(set) var performed: [GitCommand] = []

    init(features: GitFeatures) {
        self.features = features
    }

    func perform(_ command: GitCommand, progress: (@Sendable (Double) -> Void)?) async throws {
        try requireSupport(for: command)
        performed.append(command)
    }
}

@MainActor
struct ConsumerTests {

    @Test func anAppCanStyleAndLimitTheKit() {
        var style = GitUIStyle.system
        style.fontScale = 1.25
        style.showsPointingHand = true
        var features = GitFeatures.all
        features.remove([.merge], reason: "Only in the project root")
        let view = GitBanner(symbol: "xmark.octagon", message: "Push rejected.", tone: .negative)
            .gitUIStyle(style)
            .gitFeatures(features)
        #expect(NSHostingController(rootView: view).sizeThatFits(in: NSSize(width: 400, height: 400)).height > 0)
    }

    @Test func aTrailingClosureAfterATitleIsTheAction() {
        let banner = GitBanner(symbol: "arrow.down.circle", message: "Behind.", actionTitle: "Pull") {}
        let fields = Dictionary(uniqueKeysWithValues: Mirror(reflecting: banner).children.compactMap { child in
            child.label.map { ($0, child.value) }
        })
        #expect((fields["action"] as? (() -> Void)?).flatMap { $0 } != nil)
        #expect((fields["onDismiss"] as? (() -> Void)?).flatMap { $0 } == nil)
    }

    @Test func anAppCanShowADiffWithItsOwnRowsAndActions() throws {
        let patch = "diff --git a/a.swift b/a.swift\n--- a/a.swift\n+++ b/a.swift\n@@ -1,2 +1,2 @@\n let a = 1\n-let b = 2\n+let b = 3\n"
        let diff = try #require(DiffParser.parse(patch).first)
        let options = GitDiffOptions(layout: .constant(.split), wrapsLines: .constant(true), imageMode: .constant(.slider))
        let note = GitDiffAnnotation(id: "note", side: .new, revision: "body",
                                     anchor: { _ in GitDiffLineAnchor(hunk: 0, line: 2) }, height: { _ in 40 },
                                     content: { context in
                                         Button("Edit") { context.presentPopover { close in Button("Save", action: close) } }
                                             .frame(width: context.width)
                                     })
        let annotations = GitDiffAnnotations([note], addTitle: "Add Comment", maxWidth: 480) { picked, close in
            picked.indices.isEmpty || picked.filePath.isEmpty ? nil : AnyView(Button(picked.side == .new ? "New" : picked.hunk.header, action: close))
        }
        let host = GitUIHost(copy: { _ in }, toast: { _ in }, openFile: { _, _ in })
        let staging = FileStatus.added.supportsHunkActions
            ? GitDiffStaging(side: .unstaged) { (_: HunkAction, _: HunkData, _: [GroveKit.DiffLine]) in } : nil
        let pane = GitDiffPane(diff: diff, path: "a.swift", status: .modified, options: options, staging: staging,
                               sideSwitch: GitDiffSideSwitch(side: .unstaged, select: { _ in }),
                               ignoresWhitespace: .constant(false), annotations: annotations,
                               leading: { Image(systemName: "swift") }, accessory: { Toggle("Viewed", isOn: .constant(false)) })
            .gitUIHost(host)
            .frame(width: 640, height: 320)

        let view = NSHostingView(rootView: pane)
        let window = NSWindow(contentRect: NSRect(x: -8000, y: -8000, width: 640, height: 320),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        defer { window.close() }
        view.layoutSubtreeIfNeeded()
        // An app's driver finds the table by its public type.
        func table(in view: NSView) -> GitDiffTableView? {
            (view as? GitDiffTableView) ?? view.subviews.lazy.compactMap(table).first
        }
        let found = try #require(table(in: view))
        found.selectRowIndexes([2], byExtendingSelection: false)
        #expect(found.numberOfRows == 4)
        #expect(Array(found.selectedRowIndexes) == [2])
        #expect(GitImageDiffView.supports(path: "logo.PNG") && !GitImageDiffView.supports(path: "logo.svg"))
        _ = GitDiffView(diff: diff, options: options, fitsContent: true)
        _ = GitDiffImages.commit("HEAD", in: MockGitRepository())
    }

    @Test func anAppCanWrapTheCommands() async {
        var features = GitFeatures.all
        features.remove([.merge], reason: "Only in the project root")
        let commands = HostCommands(features: features)
        await #expect(throws: GitFeatureError.self) { try await commands.perform(.merge("topic", squash: false)) }
    }

    @Test func anAppCanPresentAndSubmitTheDialogs() async throws {
        let repository = MockGitRepository()
        let refs = RepositoryRefs(repository: repository)
        refs.replace(localBranches: MockData.branches.filter(\.isLocal), remotes: MockData.remotes)
        let commands = HostCommands(features: .all)
        var context = GitDialogContext(repository: repository, refs: refs, commands: commands)
        context.preferredBranch = "develop"
        context.onChange = {}
        context.pinBranch = { _ in }
        context.onRemoteAdded = { _ in }
        context.worktrees = GitDialogWorktrees(checkingOut: { _ in nil }, remove: { _, _, _, _ in }, open: { _ in })
        let presenter = GitDialogPresenter()
        presenter.onClose = { _, _ in }
        presenter.present(.push(), context: context)
        _ = Text("Window").gitDialogs(presenter)
        _ = GitDialogView(.merge, context: context) { _ in }

        var merge = GitMergeForm(candidates: ["develop"])
        merge.squash = true
        try await merge.submit(in: context, progress: nil)
        #expect(commands.performed == [.merge("develop", squash: true)])
        var push = GitPushForm(branch: MockData.branches[0], isHead: true, remotes: MockData.remotes)
        push.tags = .follow
        #expect(push.unsupportedReason(.all) == nil && push.commands.count == 1)

        // An app's own sheets build on the same template.
        _ = GitDialogSheet(title: "Clone", primaryTitle: "Clone", onCancel: {}, onPrimary: {}) {
            GitDialogCard {
                GitDialogField("URL") { GitComboBox(text: .constant(""), items: [], placeholder: "URL").gitInitialFocus() }
                GitDialogPathField(path: "~/Projects") {}
                GitDialogOptionRow(isOn: .constant(true), label: "Recurse")
            }
            GitDialogOptionsSection { Text("More") }
        }
        #expect(GitDialogField<EmptyView>.labelWidth > 0)
    }
    @Test func anAppCanShowTheWorkingCopyWithItsOwnParts() async {
        let viewModel = WorkingCopyViewModel(repository: MockGitRepository())
        viewModel.commands = HostCommands(features: .all)
        var host = GitWorkingCopyHost()
        host.openFile = { _ in }
        host.profiles = GitIdentityProfiles(load: { [] }, save: { _, _ in }, remove: { _ in }, manage: {})
        host.manageTemplates = {}
        host.present = { (_: GitDialog) in }
        host.openInDiffTool = { _, _ in }
        host.openInMergeTool = { _ in }
        host.choosePatch = { nil }
        host.choosePatchDestination = { _, _ in nil }
        host.onMessageFocus = { _ in }
        host.onEvent = { (event: GitWorkingCopyEvent) in _ = event == .patchCreated(succeeded: true) }
        host.showsErrors = false
        host.leftWidth = .constant(320)
        host.diffOptions = GitDiffOptions()
        var slots = GitWorkingCopySlots()
        slots.filesHeader = AnyView(Text("Scope"))
        slots.rowAccessory = { _ in AnyView(Image(systemName: "eye")) }
        slots.rowMenu = { _, _ in AnyView(Button("Blame") {}) }
        slots.composerAccessory = AnyView(Button("Review") {})
        slots.diff = { entry in AnyView(Text(entry.path)) }
        slots.replacement = (files: AnyView(Text("Files")), detail: AnyView(Text("Diff")))
        let view = GitWorkingCopyView(viewModel: viewModel, host: host, slots: slots)
            .gitWorkingCopyDialogs(viewModel)
            .frame(width: 1000, height: 600)
        _ = NSHostingController(rootView: view).sizeThatFits(in: NSSize(width: 1000, height: 600))
        _ = GitConflictsView(viewModel: viewModel, host: host) {}
        _ = GitAvatar(name: "Ada", size: 22)
        let entry = MockData.statusEntries[0]
        await viewModel.saveConflictResolution(entry, contents: "merged")
        #expect((viewModel.commands as? HostCommands)?.performed == [.saveConflictResolution(path: entry.path, contents: "merged")])
    }
    @Test func anAppCanShowTheCompactWorkingCopyInAPanel() {
        let viewModel = WorkingCopyViewModel(repository: MockGitRepository())
        var host = GitWorkingCopyHost()
        host.compactDiffHeight = .constant(300)
        host.presentsDialogs = false
        var slots = GitWorkingCopySlots()
        slots.filesDetail = "3 changed · 1 of 3 viewed"
        slots.trackedFileMenu = { path in AnyView(Button("Blame \(path)") {}) }
        for layout in [GitWorkingCopyLayout.automatic, .compact(composer: false), .compact(composer: true)] {
            let view = GitWorkingCopyView(viewModel: viewModel, host: host, slots: slots, layout: layout).frame(width: 300, height: 600)
            _ = NSHostingController(rootView: view).sizeThatFits(in: NSSize(width: 300, height: 600))
        }
    }

    @Test func anAppCanShowHistoryCompareFileHistoryAndTheRebasePlannerItsWay() async {
        let repository = MockGitRepository()
        let history = HistoryViewModel(repository: repository)
        let commands = HostCommands(features: .all)
        history.commands = commands
        history.onOpenBlame = { _, _ in }
        history.onRebaseStopped = {}
        let context = GitDialogContext(repository: repository, refs: history.refs, commands: commands)
        var host = GitHistoryHost()
        host.title = "feature vs main"
        host.ownCommits = []
        host.compare = { _, _ in }
        host.interactiveRebase = { (commit: CommitInfo) in _ = commit.id }
        host.showInHistory = { _ in }
        host.openBlame = { _, _ in }
        host.avatarURL = { _, _ in nil }
        host.diffOptions = GitDiffOptions()
        host.compareAnnotations = { _, _, _ in nil }
        let views: [AnyView] = [
            AnyView(GitHistoryView(viewModel: history, dialogs: context, host: host)),
            AnyView(GitCompareView(context: context, base: .constant("main"), compare: .constant("feature"), host: host)),
            AnyView(GitFileHistoryView(viewModel: history.fileHistory(path: "README.md"))),
            AnyView(GitInteractiveRebaseView(viewModel: history, from: "abc") {}),
        ]
        for view in views {
            _ = NSHostingController(rootView: view.frame(width: 1000, height: 600)).sizeThatFits(in: NSSize(width: 1000, height: 600))
        }
        _ = NSHostingController(rootView: GitCommitRow(commit: MockData.commits[0])).sizeThatFits(in: NSSize(width: 400, height: 60))
        let table: GitCommitTableView.Type = GitCommitTableView.self
        #expect(table is NSTableView.Type)
        await history.loadInitial()
        if let commit = history.commits.dropFirst().first {
            await history.cherryPick(commit)
            await history.reset(to: commit, mode: .soft)
            #expect(commands.performed == [.cherryPick(commit.id), .reset(to: commit.id, mode: .soft)])
        }
    }

    @Test func anAppCanShowBlameItsWay() async {
        let blame = BlameViewModel(repository: MockGitRepository())
        var host = GitBlameHost()
        host.pick = { (path: String?) in _ = path }
        host.showInHistory = { _ in }
        host.fileIcon = { _ in AnyView(Image(systemName: "doc")) }
        await blame.open(file: "README.md")
        let view = GitBlameView(viewModel: blame, host: host).gitUIHost(GitUIHost(openFile: { _, _ in }))
        _ = NSHostingController(rootView: view.frame(width: 1000, height: 600)).sizeThatFits(in: NSSize(width: 1000, height: 600))
        let list = GitSelectableList(items: [Item(id: "a")], selection: "a", onSelect: { _ in }) { Text($0.id) }
        _ = NSHostingController(rootView: list.frame(width: 300, height: 200)).sizeThatFits(in: NSSize(width: 300, height: 200))
        _ = NSHostingController(rootView: Text("row").gitSelectableRow(isSelected: true)).sizeThatFits(in: NSSize(width: 300, height: 40))
        let table: GitBlameTableView.Type = GitBlameTableView.self
        #expect(table is NSTableView.Type)
        blame.close()
        #expect(blame.selectedFile == nil)
    }

    @Test func anAppCanShowRefsStashesReflogAndReviewItsWay() async {
        let repository = MockGitRepository()
        let refs = RepositoryRefs(repository: repository)
        var features = GitFeatures.all
        features.remove([.checkout, .createBranch], reason: "Only in the project root")
        let commands = HostCommands(features: features)
        let actions = RefActionsViewModel(repository: repository, refs: refs)
        actions.commands = commands
        actions.onRepositoryChanged = {}
        let model = GitRefsModel(actions: actions)
        await refs.refresh()
        var host = GitRefsHost()
        host.marks = GitBranchMarks(pinned: ["develop"], archived: ["old"], protected: ["main"], base: "develop")
        host.setPinned = { _, _ in }
        host.setArchived = { _, _ in }
        host.hiddenBranches = ["feature/auth"]
        host.showsFailures = false
        host.compare = { _, _ in }
        host.branchMenu = { _ in AnyView(Button("Mine") {}) }
        host.drop = { payload, _, _ in
            GitRefCustomDrop(id: payload, title: "Move", message: "", symbol: "square", primaryTitle: "Move", fields: []) {}
        }
        let dialogs = GitDialogContext(repository: repository, refs: refs, commands: commands)
        var selection: GitRefItem? = .branch("main")
        let sidebar = GitRefsSidebar(model: model, dialogs: dialogs, presenter: GitDialogPresenter(),
                                     selection: Binding(get: { selection }, set: { selection = $0 }), host: host) {
            Text("Header")
        } branches: {
            Text("stack").gitRefBranchRow(refs.localBranches[0])
        }
        _ = NSHostingController(rootView: sidebar.gitFeatures(features).frame(width: 280, height: 600))
            .sizeThatFits(in: NSSize(width: 280, height: 600))
        #expect(model.localBranchGroups(host.marks, hiding: host.hiddenBranches).flatMap(\.branches).allSatisfy { $0.name != "main" })
        #expect(model.handleDrop("develop", onBranch: refs.localBranches[0], option: false, host: host))
        var expansion = GitFolderExpansion(containsHEAD: true)
        expansion.toggle(to: false)
        #expect(!expansion.isExpanded)

        let stashes = StashesViewModel(repository: repository)
        stashes.commands = commands
        let reflog = ReflogViewModel(repository: repository)
        let review = BranchesReviewViewModel(repository: repository, refs: refs)
        for view in [AnyView(GitStashesView(viewModel: stashes, dialogs: dialogs, options: GitDiffOptions(), hasChanges: false)),
                     AnyView(GitReflogView(viewModel: reflog, dialogs: dialogs)),
                     AnyView(GitBranchesReviewView(viewModel: review)),
                     AnyView(GitChangesetBrowser(files: [], selectedPath: nil) { _ in }),
                     AnyView(GitSidebarRow(title: "main", symbol: "tag") { GitAheadBehind(ahead: 1, behind: 2) })] {
            _ = NSHostingController(rootView: view.frame(width: 900, height: 600)).sizeThatFits(in: NSSize(width: 900, height: 600))
        }
    }

    private struct Item: Identifiable { let id: String }
}
#endif
