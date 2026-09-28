// CommitMessageDrafterTests.swift
// GroveTests
//
// The Messages API request and response handling for AI commit messages, against a stubbed URLSession.

import Foundation
import Testing
@testable import Grove

/// Answers every request with the canned response and records what was sent.
final class StubAnthropicProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var lastRequestBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequestBody = request.httpBody ?? request.httpBodyStream.map(Self.read)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubAnthropicProtocol.self]
        return URLSession(configuration: config)
    }
}

@MainActor
@Suite(.serialized)
struct CommitMessageDrafterTests {

    private static func reply(_ text: String, stop: String = "end_turn") -> Data {
        let body: [String: Any] = ["content": [["type": "text", "text": text]], "stop_reason": stop]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }

    @Test func buildsAMessagesRequest() throws {
        let request = try CommitMessageDrafter.request(diff: "diff --git a/x b/x\n", apiKey: "test-key", branch: "main")
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "claude-sonnet-5")
        let format = (body["output_config"] as? [String: Any])?["format"] as? [String: Any]
        #expect(format?["type"] as? String == "json_schema")
    }

    @Test func refusesEmptyAndHugeDiffs() {
        #expect(throws: CommitMessageDrafter.Failure.emptyDiff) {
            try CommitMessageDrafter.request(diff: "", apiKey: "k", branch: nil)
        }
        let huge = String(repeating: "x", count: CommitMessageDrafter.maxDiffBytes + 1)
        #expect(throws: CommitMessageDrafter.Failure.diffTooLarge(huge.utf8.count)) {
            try CommitMessageDrafter.request(diff: huge, apiKey: "k", branch: nil)
        }
    }

    @Test func parsesTheStructuredReply() throws {
        let draft = try CommitMessageDrafter.parse(Self.reply(#"{"summary":"fix: guard nil window ","description":"Avoids a crash."}"#))
        #expect(draft == CommitMessageDraft(summary: "fix: guard nil window", description: "Avoids a crash."))
        #expect(throws: CommitMessageDrafter.Failure.refused) {
            try CommitMessageDrafter.parse(Self.reply("", stop: "refusal"))
        }
        #expect(throws: CommitMessageDrafter.Failure.unreadableResponse) {
            try CommitMessageDrafter.parse(Self.reply("not json"))
        }
    }

    @Test func surfacesAPIErrors() async {
        StubAnthropicProtocol.status = 401
        StubAnthropicProtocol.body = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        let drafter = CommitMessageDrafter(session: StubAnthropicProtocol.session)
        await #expect(throws: CommitMessageDrafter.Failure.api(status: 401, message: "invalid x-api-key")) {
            _ = try await drafter.draft(diff: "diff", apiKey: "bad", branch: nil)
        }
    }

    @Test func viewModelFillsTheComposerFromTheDraft() async throws {
        StubAnthropicProtocol.status = 200
        StubAnthropicProtocol.body = Self.reply(#"{"summary":"feat: add greeter","description":"Says hello."}"#)
        let vm = WorkingCopyViewModel(repository: MockGitRepository())
        vm.messageDrafter = CommitMessageDrafter(session: StubAnthropicProtocol.session)
        vm.loadAnthropicKey = { "test-key" }
        await vm.refresh()
        await vm.draftCommitMessage()
        #expect(vm.aiDraft == AIDraftState())
        #expect(vm.commitSubject == "feat: add greeter")
        #expect(vm.commitBody == "Says hello.")
        let sent = try #require(StubAnthropicProtocol.lastRequestBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(sent.contains("diff --git"))
    }

    @Test func missingKeyExplainsInsteadOfSending() async {
        StubAnthropicProtocol.lastRequestBody = nil
        let vm = WorkingCopyViewModel(repository: MockGitRepository())
        vm.messageDrafter = CommitMessageDrafter(session: StubAnthropicProtocol.session)
        vm.loadAnthropicKey = { nil }
        await vm.draftCommitMessage()
        #expect(vm.aiDraft.needsKey)
        #expect(vm.aiDraft.errorMessage?.contains("Preferences") == true)
        #expect(StubAnthropicProtocol.lastRequestBody == nil)
    }

    @Test func keychainRoundTripsOnATestAccount() throws {
        let account = "grove-tests-only-\(UUID().uuidString)"
        defer { try? AnthropicKeyStore.delete(account: account) }
        #expect(AnthropicKeyStore.key(account: account) == nil)
        try AnthropicKeyStore.save("  sk-ant-test  ", account: account)
        #expect(AnthropicKeyStore.key(account: account) == "sk-ant-test")
        try AnthropicKeyStore.save("sk-ant-other", account: account)
        #expect(AnthropicKeyStore.key(account: account) == "sk-ant-other")
        try AnthropicKeyStore.delete(account: account)
        #expect(AnthropicKeyStore.key(account: account) == nil)
    }
}
