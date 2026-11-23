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
}
#endif
