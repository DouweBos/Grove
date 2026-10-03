// RepositorySettingsTests.swift
// GroveTests
//
// Reloading repository settings keeps unsaved edits.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@MainActor
struct RepositorySettingsTests {

    typealias Snapshot = RepositorySettingsViewModel.Snapshot

    @Test func reloadKeepsUnsavedDraft() async {
        let vm = RepositorySettingsViewModel(repository: MockGitRepository())
        #expect(!vm.hasLoaded)
        await vm.load()
        #expect(vm.hasLoaded)
        vm.setUserName("Draft Name")
        await vm.load()
        #expect(vm.draft.userName == "Draft Name")
        #expect(vm.hasChanges)
    }

    @Test func rebaseTakesNewValuesForUntouchedFieldsOnly() {
        let old = Snapshot(userName: "a", userEmail: "a@x", pullStrategy: .inherit,
                           remoteURLs: ["origin": "o1", "fork": "f1"])
        var draft = old
        draft.userName = "edited"
        draft.remoteURLs["fork"] = "f-edited"
        let new = Snapshot(userName: "b", userEmail: "b@x", pullStrategy: .rebase,
                           remoteURLs: ["origin": "o2", "fork": "f2"])

        let result = RepositorySettingsViewModel.rebase(draft: draft, from: old, onto: new)
        #expect(result == Snapshot(userName: "edited", userEmail: "b@x", pullStrategy: .rebase,
                                   remoteURLs: ["origin": "o2", "fork": "f-edited"]))
    }

    @Test func rebaseDropsEditsForRemovedRemotes() {
        let old = Snapshot(remoteURLs: ["gone": "g1"])
        var draft = old
        draft.remoteURLs["gone"] = "g-edited"
        let result = RepositorySettingsViewModel.rebase(draft: draft, from: old, onto: Snapshot())
        #expect(result.remoteURLs.isEmpty)
    }
}
