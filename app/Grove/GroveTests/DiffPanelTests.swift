// DiffPanelTests.swift
// GroveTests

@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct DiffPanelTests {

    @Test(arguments: [FileStatus.modified, .added, .deleted, .renamed, .copied, .untracked])
    func offersHunkActionsForWhatGroveKitSupports(_ status: FileStatus) {
        let staged = StatusEntry(id: "f", path: "f", indexStatus: status, workdirStatus: .unmodified)
        let unstaged = StatusEntry(id: "f", path: "f", indexStatus: .unmodified, workdirStatus: status)
        #expect(DiffPanelView.offersHunkActions(staged, showingStaged: true))
        #expect(DiffPanelView.offersHunkActions(unstaged, showingStaged: false))
    }

    @Test(arguments: [FileStatus.typeChange, .conflicted, .ignored, .unmodified])
    func offersNoneForAllOrNothingChanges(_ status: FileStatus) {
        let entry = StatusEntry(id: "f", path: "f", indexStatus: status, workdirStatus: status)
        #expect(!DiffPanelView.offersHunkActions(entry, showingStaged: true))
        #expect(!DiffPanelView.offersHunkActions(entry, showingStaged: false))
    }

    @Test func readsTheSideThatIsShown() {
        let entry = StatusEntry(id: "f", path: "f", indexStatus: .added, workdirStatus: .typeChange)
        #expect(DiffPanelView.offersHunkActions(entry, showingStaged: true))
        #expect(!DiffPanelView.offersHunkActions(entry, showingStaged: false))
    }
}
