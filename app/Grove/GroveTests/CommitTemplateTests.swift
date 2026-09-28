// CommitTemplateTests.swift
// GroveTests
//
// The commit template store, git's commit.template, and templates in the composer.

import Foundation
import Testing
@testable import Grove

@MainActor
struct CommitTemplateStoreTests {

    @Test func persistsEveryChange() {
        var saved: [CommitTemplate] = []
        let store = CommitTemplateStore(load: { [] }, save: { saved = $0 })
        var template = store.add()
        template.summary = "fix(ui): "
        store.update(template)
        #expect(saved.map(\.summary) == ["fix(ui): "])
        store.delete(template.id)
        #expect(saved.isEmpty)
    }

    @Test func startsWithDefaultsWhenNothingIsStored() {
        let store = CommitTemplateStore(load: { nil }, save: { _ in })
        #expect(store.templates.first?.summary == "feat: ")
    }

    @Test func parsesAGitTemplateWithoutComments() throws {
        let template = try #require(CommitTemplate(gitTemplate: "# Explain why\nfeat: \n\nWhy:\n# more help\nIssue:\n"))
        #expect(template.summary == "feat: ")
        #expect(template.body == "Why:\nIssue:")
        #expect(CommitTemplate(gitTemplate: "# only comments\n") == nil)
    }
}

@MainActor
@Suite(.serialized)
struct ComposerTemplateTests {

    private let root: URL
    private let store = CommitTemplateStore(load: { [CommitTemplate(name: "Bug", summary: "fix: ", body: "Steps:")] }, save: { _ in })

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-template-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try git(["init", "-q", "-b", "main"])
        try Data("Summary here\n\n# comment\nDetails here\n".utf8).write(to: root.appendingPathComponent("template.txt"))
        try git(["config", "commit.template", root.appendingPathComponent("template.txt").path])
    }

    @Test func prefillsFromGitTemplateOnlyOnce() async throws {
        let repo = try await GitRepository(path: root)
        let vm = WorkingCopyViewModel(repository: repo, templateStore: store)
        await vm.refresh()
        #expect(vm.commitSubject == "Summary here")
        #expect(vm.commitBody == "Details here")
        #expect(vm.availableTemplates.map(\.name) == ["Git Template (commit.template)", "Bug"])

        vm.commitSubject = ""
        vm.commitBody = ""
        await vm.refresh()
        #expect(vm.commitSubject.isEmpty)
    }

    @Test func slashAutocompleteUsesTheStore() async throws {
        try git(["config", "--unset", "commit.template"])
        let repo = try await GitRepository(path: root)
        let vm = WorkingCopyViewModel(repository: repo, templateStore: store)
        await vm.refresh()
        vm.commitSubject = "/bu"
        let suggestion = try #require(vm.autoCompleteSuggestions.first)
        #expect(suggestion.title == "Bug")
        vm.applyAutoComplete(suggestion)
        #expect(vm.commitSubject == "fix: ")
        #expect(vm.commitBody == "Steps:")
    }

    @discardableResult
    private func git(_ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = root
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
