// GitmojiTests.swift
// GroveKitTests
//
// The bundled gitmoji list, the `:` autocomplete and the picker's summary prefix.

import Testing
@testable import GroveKit

@MainActor
struct GitmojiTests {

    @Test func loadsTheBundledList() throws {
        #expect(Gitmoji.all.count > 60)
        let sparkles = try #require(Gitmoji.all.first { $0.code == ":sparkles:" })
        #expect(sparkles.emoji == "✨")
    }

    @Test func searchPrefersCodeMatches() {
        let results = Gitmoji.search("bug")
        #expect(results.first?.code == ":bug:")
        #expect(Gitmoji.search("performance").first?.code == ":zap:")
    }

    @Test func colonTriggersOnlyAtAWordStart() {
        #expect(WorkingCopyViewModel.gitmojiQuery(in: ":spa") == "spa")
        #expect(WorkingCopyViewModel.gitmojiQuery(in: "fix :bu") == "bu")
        #expect(WorkingCopyViewModel.gitmojiQuery(in: "feat:") == nil)
        #expect(WorkingCopyViewModel.gitmojiQuery(in: "feat: add") == nil)
    }

    @Test func autocompleteInsertsTheEmoji() throws {
        let vm = WorkingCopyViewModel(repository: MockGitRepository())
        vm.commitSubject = ":sparkl"
        #expect(vm.autoCompleteTrigger == .gitmoji)
        let suggestion = try #require(vm.autoCompleteSuggestions.first)
        vm.applyAutoComplete(suggestion)
        #expect(vm.commitSubject == "✨ ")
    }

    @Test func arrowKeysChooseWhatReturnInserts() {
        let vm = WorkingCopyViewModel(repository: MockGitRepository())
        vm.commitSubject = ":b"
        let second = vm.autoCompleteSuggestions[1]
        vm.moveAutoCompleteHighlight(by: 1)
        #expect(vm.autoCompleteHighlight == second.id)
        #expect(vm.acceptAutoComplete())
        #expect(vm.commitSubject == second.insertText)
        #expect(!vm.acceptAutoComplete())
    }

    @Test func pickerReplacesALeadingGitmoji() throws {
        let bug = try #require(Gitmoji.all.first { $0.code == ":bug:" })
        let zap = try #require(Gitmoji.all.first { $0.code == ":zap:" })
        #expect(Gitmoji.prefixing("Fix login", with: bug) == "🐛 Fix login")
        #expect(Gitmoji.prefixing("🐛 Fix login", with: zap) == "⚡️ Fix login")
    }
}
