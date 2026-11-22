// Diff/Highlighting/DiffSyntax.swift
// GroveUIKit
//
// Lexes a hunk. Token kinds and ranges only: colors come from the style when a line draws.

#if os(macOS)
import Foundation
import GroveKit

nonisolated enum DiffSyntax {

    /// Spans per line index. Old and new sides are lexed separately so a comment opened in a
    /// deleted line doesn't swallow the added lines after it. Nil when cancelled.
    static func spans(for lines: [DiffLine], language: SyntaxLanguage) -> [[SyntaxSpan]]? {
        let tokenizer = SyntaxTokenizer(language: language)
        var oldState = SyntaxTokenizer.State.normal
        var newState = SyntaxTokenizer.State.normal
        var result: [[SyntaxSpan]] = []
        result.reserveCapacity(lines.count)
        for line in lines {
            if result.count % 512 == 0, Task.isCancelled { return nil }
            switch line.type {
            case .deletion:
                result.append(tokenizer.tokenize(line.content, state: &oldState))
            case .addition:
                result.append(tokenizer.tokenize(line.content, state: &newState))
            case .context:
                let before = newState
                let spans = tokenizer.tokenize(line.content, state: &newState)
                if oldState == before {
                    oldState = newState
                } else {
                    _ = tokenizer.tokenize(line.content, state: &oldState)
                }
                result.append(spans)
            }
        }
        return result
    }
}
#endif
