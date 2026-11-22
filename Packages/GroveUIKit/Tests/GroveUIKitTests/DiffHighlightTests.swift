// DiffHighlightTests.swift
// GroveUIKitTests
//
// The diff syntax lexer, its per-side state across lines, and layering with word highlights.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI
import Testing
@testable import GroveUIKit

@MainActor
struct DiffHighlightTests {

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
            DiffLine(id: "1", type: .addition, content: "let value = 1", oldLineNumber: nil, newLineNumber: 1),
        ]
        let spans = DiffSyntax.spans(for: lines, language: .swift)
        #expect(spans?[1].first?.kind == .keyword)
    }

    @Test func contextAfterADivergenceFollowsBothSides() {
        let lines = [
            DiffLine(id: "0", type: .deletion, content: "/* opens on the old side"),
            DiffLine(id: "1", type: .context, content: "let a = 1 */"),
            DiffLine(id: "2", type: .deletion, content: "let old = 1"),
        ]
        let spans = DiffSyntax.spans(for: lines, language: .swift)
        #expect(spans?[1].first?.kind == .keyword)
        #expect(spans?[2].first?.kind == .keyword)
    }

    @Test func layersColorsOverWordHighlights() {
        let words = DiffWordHighlighter.changes(deletion: "let a = 1", addition: "let b = 2").addition
        let spans = [SyntaxSpan(range: 0..<3, kind: .keyword), SyntaxSpan(range: 8..<9, kind: .number)]
        let text = DiffLineText("let b = 2", spans: spans, words: words)
        #expect(text.text as String == "let b = 2")
        let palette = DiffPalette(.system)
        let drawn = DiffTextDrawing(metrics: DiffMetrics(scale: 1), palette: palette)
            .attributed(text, range: text.range(ofLine: 0), color: palette.text)
        let key = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        func color(at index: Int) -> CGColor? {
            drawn.attribute(key, at: index, effectiveRange: nil).map { $0 as! CGColor }
        }
        #expect(color(at: 0) == palette.color(.keyword).cgColor)
        // The changed token keeps its word highlight and gains the number color.
        #expect(color(at: 8) == palette.color(.number).cgColor)
        #expect(text.words.contains { NSLocationInRange(8, $0) })
    }

    @Test func theStyleSuppliesTheColors() {
        var style = GitUIStyle.system
        style.syntax.keyword = Color(red: 1, green: 0, blue: 0)
        let red = DiffPalette(style).color(.keyword).usingColorSpace(.sRGB)
        #expect(red?.redComponent == 1 && red?.greenComponent == 0)
    }

    @Test func lexesALargeHunkQuickly() {
        let lines = (0..<20_000).map { index in
            DiffLine(id: "\(index)", type: .addition, content: "    let value\(index) = compute(\"item\", \(index)) // note",
                     oldLineNumber: nil, newLineNumber: index)
        }
        let start = Date()
        let spans = DiffSyntax.spans(for: lines, language: .swift)
        let elapsed = Date().timeIntervalSince(start)
        #expect(spans?.count == 20_000)
        #expect(elapsed < 1.5, "Lexing 20k lines took \(elapsed)s")
    }

    // MARK: Words

    @Test func marksOnlyTheWordsThatChanged() {
        let changes = DiffWordHighlighter.changes(deletion: "log(index)", addition: "log(index + 1)")
        #expect(changes.deletion.isEmpty)
        #expect(changes.addition == [9..<13])
        let renamed = DiffWordHighlighter.changes(deletion: "let old_name = 1", addition: "let newName = 1")
        #expect(renamed.deletion == [4..<12])
        #expect(renamed.addition == [4..<11])
    }

    @Test func aBlankSideMarksTheOtherThroughout() {
        #expect(DiffWordHighlighter.changes(deletion: "", addition: "abc").addition == [0..<3])
        let long = String(repeating: "x ", count: 200)
        #expect(DiffWordHighlighter.changes(deletion: long, addition: "x").deletion == [0..<400])
    }

    @Test func rangesLandOnTheTextAsDrawn() {
        let content = "\t🙂 let"
        let text = DiffLineText(content, spans: [SyntaxSpan(range: 3..<6, kind: .keyword)])
        #expect(text.text as String == "    🙂 let")
        #expect(text.text.substring(with: text.tokens[0].range) == "let")
    }

    @Test func aCopyKeepsItsTabs() {
        let text = DiffLineText("\tlet a\t= 1")
        #expect(text.original(NSRange(location: 0, length: 9)) == "\tlet a")
        #expect(text.original(NSRange(location: 9, length: 6)) == "\t= ")
        #expect(text.text.substring(with: text.word(at: 5)) == "let")
    }

    // MARK: Cache

    private func swiftHunk(lines count: Int) -> HunkData {
        DiffFixture.diff([String(repeating: "+", count: count)], path: "a.swift") { "let v = \($0)" }.hunks[0]
    }

    @Test func shortHunksAreColoredAsTheyShow() {
        let highlights = DiffHighlights()
        highlights.reset(hunks: [swiftHunk(lines: 3)], path: "a.swift")
        #expect(highlights.syntax(hunk: 0, line: 2).first?.kind == .keyword)
        highlights.reset(hunks: [swiftHunk(lines: 3)], path: "a.txt")
        #expect(highlights.syntax(hunk: 0, line: 2).isEmpty)
    }

    @Test(.timeLimit(.minutes(1))) func longHunksAreColoredOffTheMainThread() async {
        let highlights = DiffHighlights()
        let hunk = swiftHunk(lines: DiffHighlights.immediateLines + 1)
        highlights.reset(hunks: [hunk], path: "a.swift")
        let changed: Set<Int> = await withCheckedContinuation { continuation in
            highlights.onChange = { continuation.resume(returning: $0) }
            #expect(highlights.syntax(hunk: 0, line: 0).isEmpty)
        }
        #expect(changed == [0])
        #expect(highlights.syntax(hunk: 0, line: 0).first?.kind == .keyword)
        // Still colored when the same hunk comes back in a refreshed diff.
        highlights.reset(hunks: [swiftHunk(lines: 1), hunk], path: "a.swift")
        #expect(highlights.syntax(hunk: 1, line: 0).first?.kind == .keyword)
    }
}
#endif
