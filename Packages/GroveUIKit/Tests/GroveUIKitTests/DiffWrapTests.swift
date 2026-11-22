// DiffWrapTests.swift
// GroveUIKitTests

#if os(macOS)
import AppKit
import GroveKit
import Testing
@testable import GroveUIKit

@MainActor
struct DiffWrapTests {

    private func wrapped(_ content: String, _ columns: Int) -> [String] {
        let text = DiffLineText(content, columns: columns)
        return (0..<text.lineCount).map { text.text.substring(with: text.range(ofLine: $0)) }
    }

    @Test func aLineThatFitsStaysWhole() {
        #expect(wrapped("hello", 5) == ["hello"])
        #expect(wrapped("", 5) == [""])
    }

    @Test func breaksAfterSpaces() {
        #expect(wrapped("let value = compute(x)", 12) == ["let value = ", "compute(x)"])
        #expect(wrapped("aa bb cc", 3) == ["aa ", "bb ", "cc"])
    }

    @Test func aWordLongerThanTheLineIsCut() {
        #expect(wrapped("abcdefghij", 4) == ["abcd", "efgh", "ij"])
        #expect(wrapped("ab cdefghij", 4) == ["ab ", "cdef", "ghij"])
    }

    @Test func indentationDoesNotBecomeALineOfItsOwn() {
        #expect(wrapped("    abcdefgh", 8) == ["    abcd", "efgh"])
    }

    @Test func tabsTakeFourColumns() {
        #expect(wrapped("\tabcdef", 8) == ["    abcd", "ef"])
    }

    @Test func wideAndComposedCharactersAreNeverSplit() {
        #expect(wrapped("日本語の文", 4) == ["日本", "語の", "文"])
        #expect(wrapped("👩‍👩‍👦👩‍👩‍👦", 4) == ["👩‍👩‍👦", "👩‍👩‍👦"])
    }

    @Test func nothingIsLostOrRepeated() {
        for content in ["let a = \"héllo wörld\" + suffix", "\t\tfunc  f( a, b )  {", "   ", "x 🙂 y 🙂 z"] {
            for columns in 1...14 {
                #expect(wrapped(content, columns).joined() == DiffLineText(content).text as String)
                #expect(DiffWrap.lineCount(content, columns: columns) == wrapped(content, columns).count)
            }
        }
    }

    @Test func noWrappedLineIsWiderThanItsColumns() {
        let content = "guard let value = cache[identifier] else { return Fallback.make(for: identifier) }"
        for columns in 8...40 {
            for line in wrapped(content, columns) {
                #expect(line.trimmingCharacters(in: .whitespaces).count <= columns)
            }
        }
    }

    @Test func rowsPastATurnsBudgetAreEstimatedUntilShown() {
        var heights = DiffRowHeights()
        for row in 0..<DiffRowHeights.measuredPerTurn {
            let count = heights.lineCount(row: row, measure: { 2 }, estimate: { 1 })
            #expect(count == 2)
        }
        let guess = heights.lineCount(row: 9_999, measure: { 3 }, estimate: { 1 })
        #expect(guess == 1)
        let needsAskingAgain = heights.willShow(row: 9_999, measure: { 3 })
        #expect(needsAskingAgain)
        let corrected = heights.takeCorrected()
        #expect(corrected == [9_999])
        let known = heights.lineCount(row: 9_999, measure: { 0 }, estimate: { 0 })
        #expect(known == 3)
    }
}
#endif
