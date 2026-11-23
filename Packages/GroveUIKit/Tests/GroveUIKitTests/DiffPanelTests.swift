// DiffPanelTests.swift
// GroveUIKitTests
//
// Moved from Grove: which changes the working copy's diff offers hunk actions for.

@testable import GroveKit
import Testing
@testable import GroveUIKit

@MainActor
struct DiffPanelTests {

    @Test(arguments: [FileStatus.modified, .added, .deleted, .renamed, .copied, .untracked])
    func offersHunkActionsForWhatGroveKitSupports(_ status: FileStatus) {
        let staged = StatusEntry(id: "f", path: "f", indexStatus: status, workdirStatus: .unmodified)
        let unstaged = StatusEntry(id: "f", path: "f", indexStatus: .unmodified, workdirStatus: status)
        #expect(WorkingCopyDetail.offersHunkActions(staged, showingStaged: true))
        #expect(WorkingCopyDetail.offersHunkActions(unstaged, showingStaged: false))
    }

    @Test(arguments: [FileStatus.typeChange, .conflicted, .ignored, .unmodified])
    func offersNoneForAllOrNothingChanges(_ status: FileStatus) {
        let entry = StatusEntry(id: "f", path: "f", indexStatus: status, workdirStatus: status)
        #expect(!WorkingCopyDetail.offersHunkActions(entry, showingStaged: true))
        #expect(!WorkingCopyDetail.offersHunkActions(entry, showingStaged: false))
    }

    @Test func readsTheSideThatIsShown() {
        let entry = StatusEntry(id: "f", path: "f", indexStatus: .added, workdirStatus: .typeChange)
        #expect(WorkingCopyDetail.offersHunkActions(entry, showingStaged: true))
        #expect(!WorkingCopyDetail.offersHunkActions(entry, showingStaged: false))
    }
}
