// SyntaxHighlightTests.swift
// GroveTests
//
// The diff syntax lexer, its per-side state across lines, and layering under word highlights.

import Foundation
@testable import GroveKit
import SwiftUI
import Testing
@testable import Grove

@MainActor
struct SyntaxHighlightTests {

    private func kinds(_ line: String, _ language: SyntaxLanguage, state: SyntaxTokenizer.State = .normal) -> [String: SyntaxKind] {
        var state = state
        let chars = Array(line)
        let spans = SyntaxTokenizer(language: language).tokenize(line, state: &state)
        return Dictionary(spans.map { (String(chars[$0.range]), $0.kind) }, uniquingKeysWith: { first, _ in first })
    }

    @Test func detectsLanguagesByExtensionAndName() {
        #expect(SyntaxLanguage.forPath("Sources/App.swift")?.name == "Swift")
        #expect(SyntaxLanguage.forPath("web/index.tsx")?.name == "JavaScript")
        #expect(SyntaxLanguage.forPath("fastlane/Fastfile")?.name == "Ruby")
        #expect(SyntaxLanguage.forPath("notes.txt") == nil)
    }

    @Test func colorsSwiftTokens() {
        let found = kinds(#"    let count = 42 // "not a string""#, .swift)
        #expect(found["let"] == .keyword)
        #expect(found["42"] == .number)
        #expect(found[#"// "not a string""#] == .comment)
        #expect(found["count"] == nil)
        let more = kinds(#"return String(repeating: "Hi \"x\"", count: 3)"#, .swift)
        #expect(more["return"] == .keyword)
        #expect(more["String"] == .type)
        #expect(more[#""Hi \"x\"""#] == .string)
    }

    @Test func colorsDeclarationKeywords() {
        #expect(kinds("struct Greeter {", .swift)["struct"] == .keyword)
        #expect(kinds("    func greet() -> String {", .swift)["func"] == .keyword)
    }

    @Test func blockCommentsAndMultilineStringsCarryAcrossLines() {
        let tokenizer = SyntaxTokenizer(language: .swift)
        var state = SyntaxTokenizer.State.normal
        _ = tokenizer.tokenize("let a = 1 /* starts", state: &state)
        #expect(state == .blockComment)
        let middle = tokenizer.tokenize("still let comment */ let b", state: &state)
        #expect(middle.first == SyntaxSpan(range: 0..<20, kind: .comment))
        #expect(middle.last?.kind == .keyword)
        #expect(state == .normal)

        var python = SyntaxTokenizer.State.normal
        let pythonTokenizer = SyntaxTokenizer(language: .python)
        _ = pythonTokenizer.tokenize(#"doc = """Starts"#, state: &python)
        #expect(python == .multilineString(#"""""#))
        _ = pythonTokenizer.tokenize(#"ends""" + def"#, state: &python)
        #expect(python == .normal)
    }

    @Test func sqlKeywordsIgnoreCase() {
        #expect(kinds("SELECT id FROM users", .sql)["SELECT"] == .keyword)
    }

    @Test func deletedLinesDoNotLeakStateIntoAddedLines() {
        let lines = [
            DiffLine(id: "0", type: .deletion, content: "/* old comment", oldLineNumber: 1, newLineNumber: nil),
            DiffLine(id: "1", type: .addition, content: "let value = 1", oldLineNumber: nil, newLineNumber: 1)
        ]
        let hunk = HunkData(id: "h", header: "@@ -1 +1 @@", oldStart: 1, oldCount: 1, newStart: 1, newCount: 1, lines: lines)
        let spans = DiffSyntax.spans(for: hunk, language: .swift)
        #expect(spans["1"]?.first?.kind == .keyword)
    }

    @Test func layersColorsOverWordHighlights() {
        let (_, added) = DiffWordHighlighter.highlight(deletion: "let a = 1", addition: "let b = 2")
        let spans = [SyntaxSpan(range: 0..<3, kind: .keyword), SyntaxSpan(range: 8..<9, kind: .number)]
        let text = DiffSyntax.attributed("let b = 2", spans: spans, base: added)
        #expect(String(text.characters) == "let b = 2")
        let runs = text.runs.map { (String(text[$0.range].characters), $0.foregroundColor, $0.backgroundColor) }
        #expect(runs.first { $0.0 == "let" }?.1 == Theme.syntaxKeyword)
        // The changed token keeps its word highlight and gains the number color.
        #expect(runs.first { $0.0 == "2" }?.1 == Theme.syntaxNumber)
        #expect(runs.first { $0.0 == "2" }?.2 == Theme.addedWordFill)
    }

    @Test func lexesALargeHunkQuickly() {
        let lines = (0..<20_000).map { index in
            DiffLine(id: "\(index)", type: .addition, content: "    let value\(index) = compute(\"item\", \(index)) // note",
                     oldLineNumber: nil, newLineNumber: index)
        }
        let hunk = HunkData(id: "big", header: "@@ -0,0 +1,20000 @@", oldStart: 0, oldCount: 0, newStart: 1, newCount: 20_000, lines: lines)
        let start = Date()
        let spans = DiffSyntax.spans(for: hunk, language: .swift)
        let elapsed = Date().timeIntervalSince(start)
        #expect(spans.count == 20_000)
        #expect(elapsed < 1.5, "Lexing 20k lines took \(elapsed)s")
    }
}
