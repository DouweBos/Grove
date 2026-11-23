// WorkingCopyViewTests.swift
// GroveUIKitTests
//
// The working copy and conflicts screens lay out in every state an app shows them in, with the app's slots.

#if os(macOS)
import AppKit
@testable import GroveKit
import SwiftUI
import Testing
@testable import GroveUIKit

/// A merge stopped on a text and a binary conflict, in a temp folder the test removes.
enum ScratchConflict {
    static func make() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("groveuikit-conflict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let script = """
        export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
        git init -q -b main . && git config user.email t@example.com && git config user.name T && git config commit.gpgsign false
        printf 'one\\n' > notes.txt && printf 'PNG\\000a' > logo.bin && git add -A && git commit -qm base
        git switch -qc other && printf 'theirs\\n' > notes.txt && printf 'PNG\\000b' > logo.bin && git commit -qam theirs
        git switch -q main && printf 'ours\\n' > notes.txt && printf 'PNG\\000c' > logo.bin && git commit -qam ours
        git merge other >/dev/null 2>&1 || true
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        process.currentDirectoryURL = root
        try process.run()
        process.waitUntilExit()
        return root
    }
}

@MainActor
@Suite(.serialized)
struct WorkingCopyViewTests {

    private func render(_ view: some View, width: CGFloat, height: CGFloat = 700) -> NSHostingView<AnyView> {
        let hosting = NSHostingView(rootView: AnyView(view.frame(width: width, height: height)))
        let window = NSWindow(contentRect: NSRect(x: -9000, y: -9000, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        window.close()
        return hosting
    }

    private var host: GitWorkingCopyHost {
        var host = GitWorkingCopyHost()
        host.openFile = { _ in }
        host.profiles = GitIdentityProfiles(load: { [UserProfile(label: "Work", userName: "Ada", email: "ada@work.com")] },
                                            save: { _, _ in }, remove: { _ in }, manage: {})
        host.manageTemplates = {}
        host.present = { _ in }
        host.showsErrors = false
        return host
    }

    private var slots: GitWorkingCopySlots {
        var slots = GitWorkingCopySlots()
        slots.filesHeader = AnyView(Text("Uncommitted"))
        slots.rowAccessory = { _ in AnyView(Image(systemName: "eye")) }
        slots.rowMenu = { _, _ in AnyView(Button("Blame") {}) }
        slots.composerAccessory = AnyView(Button("Review") {})
        return slots
    }

    @Test func aDirtyWorkingCopyLaysOutWideNarrowAndZoomed() async {
        let vm = WorkingCopyViewModel(repository: MockGitRepository())
        await vm.refresh()
        if let first = vm.unstagedFiles.first { await vm.select(first) }
        var zoomed = GitUIStyle.system
        zoomed.fontScale = 1.4
        for (width, style) in [(1100.0, GitUIStyle.system), (560.0, .system), (1100.0, zoomed)] {
            let view = render(GitWorkingCopyView(viewModel: vm, host: host, slots: slots).gitUIStyle(style), width: width)
            #expect(view.fittingSize.width > 0)
        }
        #expect(vm.selectedEntry != nil)
    }

    @Test func anOperationInProgressShowsItsBannerAndTheResolver() async throws {
        let root = try ScratchConflict.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = WorkingCopyViewModel(repository: try await GitRepository(path: root, runner: LocalGitRunner()))
        await vm.refresh()
        #expect(vm.isInOperation && Set(vm.conflictedFiles.map(\.path)) == ["notes.txt", "logo.bin"])
        await vm.resolveNextConflict()
        #expect(vm.selectedEntry?.isConflicted == true && vm.conflictVersions != nil)
        _ = render(GitWorkingCopyView(viewModel: vm, host: host), width: 1100)
        _ = render(GitConflictsView(viewModel: vm, host: host, onDone: {}), width: 1100)
        let text = await ConflictResult.read("notes.txt", from: vm.repository)
        #expect(text.text?.hasConflictMarkers == true)
        #expect(await ConflictResult.read("logo.bin", from: vm.repository).text == nil)
    }

    @Test func savingAnEditedResultResolvesTheFileThroughTheCommands() async throws {
        let root = try ScratchConflict.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = WorkingCopyViewModel(repository: try await GitRepository(path: root, runner: LocalGitRunner()))
        await vm.refresh()
        let entry = try #require(vm.conflictedFiles.first { $0.path == "notes.txt" })
        await vm.saveConflictResolution(entry, contents: "both\n")
        #expect(vm.conflictedFiles.map(\.path) == ["logo.bin"])
        #expect(vm.selectedEntry?.path == "logo.bin")
    }

    @Test func aReplacementTakesTheFilesAndDiffButKeepsTheComposer() async {
        let vm = WorkingCopyViewModel(repository: MockGitRepository())
        await vm.refresh()
        var slots = slots
        slots.replacement = (files: AnyView(Text("Turn files")), detail: AnyView(Text("Turn diff")))
        slots.diff = { _ in AnyView(Text("App diff")) }
        _ = render(GitWorkingCopyView(viewModel: vm, host: host, slots: slots), width: 1100)
    }

    @Test func aCleanWorkingCopyAndNoConflictsHaveTheirEmptyStates() async {
        let vm = WorkingCopyViewModel(repository: MockGitRepository())
        _ = render(GitWorkingCopyView(viewModel: vm), width: 900)
        _ = render(GitConflictsView(viewModel: vm), width: 900)
        #expect(vm.statusEntries.isEmpty)
    }

    @Test func theWorkingCopyGoesCompactBelowItsTwoColumns() {
        #expect(GitWorkingCopyView.compactBelow(fontScale: 1) == 652)
        #expect(GitWorkingCopyView.arrangement(width: 652, fontScale: 1, layout: .automatic) == .columns)
        #expect(GitWorkingCopyView.arrangement(width: 651, fontScale: 1, layout: .automatic) == .compact(composer: true))
        // Zoomed text needs more room before two columns fit.
        #expect(GitWorkingCopyView.arrangement(width: 800, fontScale: 1.4, layout: .automatic) == .compact(composer: true))
        #expect(GitWorkingCopyView.arrangement(width: 1400, fontScale: 1, layout: .compact(composer: false)) == .compact(composer: false))
    }

    @Test func theCompactDiffKeepsTheListItsMinimum() {
        #expect(WorkingCopyCompact.diffHeight(stored: 360, total: 700, fontScale: 1) == 360)
        #expect(WorkingCopyCompact.diffHeight(stored: 650, total: 700, fontScale: 1) == 700 - 100 - 12)
        #expect(WorkingCopyCompact.diffHeight(stored: 20, total: 700, fontScale: 1) == 160)
        #expect(WorkingCopyCompact.diffHeight(stored: 20, total: 700, fontScale: 1.5) == 240)
        // Before any drag the two split evenly.
        #expect(WorkingCopyCompact.diffHeight(stored: 0, total: 700, fontScale: 1) == 344)
        // A conflict's resolver gets the room its versions and result need.
        #expect(WorkingCopyCompact.diffHeight(stored: 360, total: 700, fontScale: 1, conflict: true) == 440)
    }

    @Test func aSidePanelShowsTheCompactListWithoutAComposer() async throws {
        let root = try ScratchConflict.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let vm = WorkingCopyViewModel(repository: try await GitRepository(path: root, runner: LocalGitRunner()))
        await vm.refresh()
        await vm.resolveNextConflict()
        var host = host
        host.presentsDialogs = false
        var slots = slots
        slots.filesDetail = "2 changed · 1 of 2 viewed"
        var zoomed = GitUIStyle.system
        zoomed.fontScale = 17.0 / 13
        for (width, style) in [(280.0, GitUIStyle.system), (420.0, .system), (420.0, zoomed)] {
            let view = GitWorkingCopyView(viewModel: vm, host: host, slots: slots, layout: .compact(composer: false))
            #expect(render(view.gitUIStyle(style), width: width).fittingSize.width > 0)
        }
        _ = render(GitWorkingCopyView(viewModel: vm, host: host, layout: .compact(composer: true)), width: 600)
        slots.replacement = (files: AnyView(Text("Turn files")), detail: AnyView(Text("Turn diff")))
        _ = render(GitWorkingCopyView(viewModel: vm, host: host, slots: slots, layout: .compact(composer: false)), width: 280)
        #expect(vm.selectedEntry?.isConflicted == true)
    }

    @Test func theFilterMatchesAnyPartOfAPathInAnyCase() async {
        let entries = [
            StatusEntry(id: "a", path: "src/Session/merge.ts", indexStatus: .unmodified, workdirStatus: .modified),
            StatusEntry(id: "b", path: "docs/README.md", indexStatus: .unmodified, workdirStatus: .modified),
        ]
        #expect(FileStatusList.Groups.matching(entries, " session ").map(\.path) == ["src/Session/merge.ts"])
        #expect(FileStatusList.Groups.matching(entries, "").count == 2)
        #expect(FileStatusList.Groups.matching(entries, "nothing").isEmpty)
    }

    @Test func allFilesListsTrackedFilesInFinderOrderAndFilters() {
        let groups = AllFilesTree.groups(["src/b10.swift", "README.md", "src/b2.swift"], entries: [])
        #expect(groups.flatMap(\.paths) == ["README.md", "src/b2.swift", "src/b10.swift"])
        let filtered = AllFilesTree.groups(["src/b10.swift", "README.md"], entries: [], filter: " SRC ")
        #expect(filtered.flatMap(\.paths) == ["src/b10.swift"])
    }

    @Test func allFilesListsUntrackedOnesTooInFinderOrder() {
        let untracked = StatusEntry(id: "n", path: "src/b3.swift", indexStatus: .unmodified, workdirStatus: .untracked)
        let groups = AllFilesTree.groups(["src/b10.swift", "README.md", "src/b2.swift"], entries: [untracked])
        #expect(groups.map(\.directory) == ["", "src"])
        #expect(groups.last?.paths == ["src/b2.swift", "src/b3.swift", "src/b10.swift"])
    }

    @Test func theEditorKeepsItsTextUntilSavedAndSavesWhatWasTyped() async throws {
        let editor = ConflictEditor()
        editor.load("<<<<<<< ours\na\n=======\nb\n>>>>>>> theirs\n")
        #expect(editor.hasMarkers && !editor.isEdited)
        #expect(await editor.currentText() == "<<<<<<< ours\na\n=======\nb\n>>>>>>> theirs\n")
        let hosting = render(ConflictTextView(editor: editor), width: 400, height: 300)
        func textView(in view: NSView) -> NSTextView? {
            (view as? NSTextView) ?? view.subviews.lazy.compactMap(textView).first
        }
        let field = try #require(textView(in: hosting))
        field.selectAll(nil)
        field.insertText("both\n", replacementRange: field.selectedRange())
        #expect(editor.isEdited && !editor.hasMarkers)
        #expect(await editor.currentText() == "both\n")
    }

    @Test func markersAndBinaryContentAreSpotted() {
        #expect("a\n<<<<<<< HEAD\nb\n=======\nc\n>>>>>>> topic\n".hasConflictMarkers)
        #expect(!"let a = \"<<<<<<<\"".hasConflictMarkers)
        #expect("PNG\u{0}".looksBinary && !"text".looksBinary)
    }
}
#endif
