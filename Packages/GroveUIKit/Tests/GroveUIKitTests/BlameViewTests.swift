// BlameViewTests.swift
// GroveUIKitTests
//
// Blame lays out wide, narrow and zoomed, follows the style live, and offers only what the app can do.

#if os(macOS)
import AppKit
@testable import GroveKit
import SwiftUI
import Testing
@testable import GroveUIKit

@MainActor
@Suite(.serialized)
struct BlameViewTests {

    private func opened(revision: String? = nil) async -> BlameViewModel {
        let vm = BlameViewModel(repository: MockGitRepository())
        await vm.loadFilesIfNeeded()
        await vm.open(file: "Sources/App.swift", revision: revision)
        return vm
    }

    private func render(_ view: some View, width: CGFloat, height: CGFloat = 600) -> (NSWindow, NSHostingView<AnyView>) {
        let hosting = NSHostingView(rootView: AnyView(view.frame(width: width, height: height)))
        let window = NSWindow(contentRect: NSRect(x: -9000, y: -9000, width: width, height: height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        for _ in 0..<3 {
            hosting.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            RunLoop.main.run(until: Date())
        }
        return (window, hosting)
    }

    private func table(in view: NSView) -> BlameNSTableView? {
        (view as? BlameNSTableView) ?? view.subviews.lazy.compactMap { table(in: $0) }.first
    }

    /// The table alone, fed as the view feeds it.
    private final class Probe {
        let coordinator: BlameTableCoordinator
        let window: NSWindow
        var copied: [String] = []
        var opened: [(String, Int?)] = []
        var revealed: [String] = []

        init(_ vm: BlameViewModel) {
            coordinator = BlameTableCoordinator(viewModel: vm)
            window = NSWindow(contentRect: NSRect(x: -8000, y: -8000, width: 900, height: 500),
                              styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = coordinator.makeView()
        }

        func show(_ vm: BlameViewModel, style: GitUIStyle = .system, opens: Bool = false, reveals: Bool = false) {
            var host = GitUIHost(copy: { [weak self] in self?.copied.append($0) })
            if opens { host.openFile = { [weak self] path, line in self?.opened.append((path, line)) } }
            coordinator.uiHost = host
            coordinator.showInHistory = reveals ? { [weak self] in self?.revealed.append($0) } : nil
            coordinator.update(lines: vm.lines, file: vm.selectedFile, revision: vm.revision, style: style)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }

        var table: BlameNSTableView { get throws { try #require(coordinator.table) } }

        func menu(row: Int) throws -> [String] {
            let menu = NSMenu()
            coordinator.fill(menu, row: row)
            return menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        }
    }

    @Test func blameLaysOutWideNarrowAndZoomed() async throws {
        let vm = await opened()
        var zoomed = GitUIStyle.system
        zoomed.fontScale = 1.4
        for (width, style) in [(1100.0, GitUIStyle.system), (560.0, .system), (1100.0, zoomed)] {
            let (window, view) = render(GitBlameView(viewModel: vm).gitUIStyle(style), width: width)
            let table = try #require(table(in: view))
            #expect(table.numberOfRows == vm.lines.count)
            #expect(table.accessibilityLabel() == "Blame")
            window.close()
        }
        #expect(GitBlameView.compactBelow(fontScale: 1) == 772)
        let picking = BlameViewModel(repository: MockGitRepository())
        await picking.loadFilesIfNeeded()
        let (window, view) = render(GitBlameView(viewModel: picking), width: 560)
        #expect(table(in: view) == nil)
        window.close()
    }

    @Test func zoomScalesTheBlame() {
        var style = GitUIStyle.system
        style.fontScale = 17.0 / 13
        let metrics = BlameMetrics(style)
        // Ported from Argus's TextScaleTests: the code font grows with the zoom.
        #expect(metrics.font.pointSize > 11.5)
        #expect(metrics.font.pointSize > BlameMetrics(.system).font.pointSize)
        #expect(metrics.lineHeight == 24)
        #expect(metrics.annotationWidth > BlameMetrics(.system).annotationWidth)
    }

    @Test func aNarrowTableKeepsMostOfItsWidthForTheCode() {
        let wide = BlameMetrics(.system, available: 2000)
        #expect(wide.annotationWidth == 420)
        #expect(wide.showsAuthor && wide.showsDate)
        let narrow = BlameMetrics(.system, available: 600)
        #expect(narrow.annotationWidth == 240)
        #expect(!narrow.showsAuthor && narrow.showsDate)
        let tiny = BlameMetrics(.system, available: 300)
        #expect(tiny.annotationWidth == 150)
        #expect(!tiny.showsDate)
        var zoomed = GitUIStyle.system
        zoomed.fontScale = 17.0 / 13
        #expect(BlameMetrics(zoomed, available: 900).annotationWidth == 360)
    }

    @Test func zoomAndThemeRestyleLiveRows() async throws {
        let vm = await opened()
        let probe = Probe(vm)
        probe.show(vm)
        #expect(try probe.table.rowHeight == 18)
        var style = GitUIStyle.system
        style.fontScale = 17.0 / 13
        style.accent = .pink
        probe.show(vm, style: style)
        #expect(try probe.table.rowHeight == 24)
        #expect(probe.coordinator.drawing?.metrics.scale == 17.0 / 13)
    }

    @Test func theMenuOffersOnlyWhatTheAppCanDo() async throws {
        let vm = await opened()
        let probe = Probe(vm)
        probe.show(vm)
        let sha = try #require(vm.lines[0].entry?.commitSHA)
        #expect(try probe.menu(row: 0) == ["Blame Before \(sha.prefix(7))", "Copy SHA", "Copy Line"])
        probe.show(vm, opens: true, reveals: true)
        #expect(try probe.menu(row: 0) == ["Open in Editor at Line", "Blame Before \(sha.prefix(7))", "Show Commit in History",
                                           "Copy SHA", "Copy Line"])
        let older = await opened(revision: "HEAD~1")
        let olderProbe = Probe(older)
        olderProbe.show(older, opens: true)
        #expect(try !olderProbe.menu(row: 0).contains("Open in Editor at Line"), "only the working tree's lines are the file's now")
    }

    @Test func gutterClicksBlameBeforeAndOptionClicksOpenTheLine() async throws {
        let vm = await opened()
        let probe = Probe(vm)
        probe.show(vm, opens: true)
        let sha = try #require(vm.lines[0].entry?.commitSHA)
        #expect(probe.coordinator.commit(row: 0, x: 10) == sha)
        #expect(probe.coordinator.commit(row: 0, x: 600) == nil)
        #expect(probe.coordinator.optionClicked(row: 2))
        #expect(probe.opened.first?.0 == "Sources/App.swift")
        #expect(probe.opened.first?.1 == 3)
        await vm.blameBefore(sha)
        #expect(vm.revision == "\(sha)^")
    }

    @Test func copyTakesTheSelectedLinesAndThePointerShowsTheHandOnlyWhenTheHostWantsIt() async throws {
        let vm = await opened()
        let probe = Probe(vm)
        probe.show(vm)
        try probe.table.selectRowIndexes([1, 2], byExtendingSelection: false)
        try probe.table.copy(nil)
        #expect(probe.copied == [vm.lines[1].text + "\n" + vm.lines[2].text])
        #expect(probe.coordinator.cursor(row: 0, x: 10) == nil)
        var style = GitUIStyle.system
        style.showsPointingHand = true
        probe.show(vm, style: style)
        #expect(probe.coordinator.cursor(row: 0, x: 10) == NSCursor.pointingHand)
        #expect(probe.coordinator.cursor(row: 0, x: 600) == NSCursor.arrow)
    }

    @Test func aPickedFileGoesThroughTheHostWhenItRoutesThem() async throws {
        let vm = BlameViewModel(repository: MockGitRepository())
        var picked: [String?] = []
        var host = GitBlameHost()
        host.pick = { picked.append($0) }
        let list = BlameFileList(viewModel: vm, host: host, pick: { host.pick?($0) })
        list.pick("README.md")
        #expect(picked == ["README.md"])
        #expect(vm.selectedFile == nil)
    }

    @Test func revisionLabels() {
        #expect(BlameFilePanel.revisionLabel(nil) == "working tree")
        #expect(BlameFilePanel.revisionLabel("abcdef1234567^") == "before abcdef1")
        #expect(BlameFilePanel.revisionLabel("feature/very-long-name") == "at feature/very")
    }
}
#endif
