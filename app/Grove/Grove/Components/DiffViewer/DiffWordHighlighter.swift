// Components/DiffViewer/DiffWordHighlighter.swift
// Grove
//
// Computes word-level differences between two strings and produces an
// AttributedString with darker highlight spans over the changed tokens.
// Darker green within green addition lines, darker
// red within red deletion lines.

import SwiftUI

// MARK: - DiffWordHighlighter

/// Stateless helper that diffs two strings at the word/token level and returns
/// `AttributedString` values suitable for display inside ``DiffLineView``.
///
/// The algorithm splits both strings into tokens (whitespace-separated words
/// plus individual punctuation runs), aligns them with a shortest-edit-script
/// approach, and marks differing spans with a background highlight.
enum DiffWordHighlighter {

    // MARK: Public API

    /// Produce attributed strings for a deletion/addition pair, with intra-line
    /// highlights marking the specific changed tokens.
    ///
    /// - Parameters:
    ///   - deletion: Content of the deleted line (without leading `-`).
    ///   - addition: Content of the added line (without leading `+`).
    /// - Returns: A tuple of `(highlightedDeletion, highlightedAddition)`.
    static func highlight(
        deletion: String,
        addition: String
    ) -> (AttributedString, AttributedString) {
        let delTokens = tokenize(deletion)
        let addTokens = tokenize(addition)

        let lcs = longestCommonSubsequence(delTokens, addTokens)

        let highlightedDeletion = buildAttributed(
            tokens: delTokens,
            lcsIndices: lcs.deletionIndices,
            baseColor: .clear,
            highlightColor: Theme.deletedWordFill
        )
        let highlightedAddition = buildAttributed(
            tokens: addTokens,
            lcsIndices: lcs.additionIndices,
            baseColor: .clear,
            highlightColor: Theme.addedWordFill
        )
        return (highlightedDeletion, highlightedAddition)
    }

    // MARK: Tokenisation

    private static func tokenize(_ string: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for char in string {
            if char.isLetter || char.isNumber || char == "_" {
                current.append(char)
            } else {
                if !current.isEmpty {
                    tokens.append(current)
                    current = ""
                }
                tokens.append(String(char))
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    // MARK: LCS

    private struct LCSResult {
        /// Indices into the deletion token array that are in the LCS (unchanged).
        let deletionIndices: Set<Int>
        /// Indices into the addition token array that are in the LCS (unchanged).
        let additionIndices: Set<Int>
    }

    private static func longestCommonSubsequence(
        _ a: [String],
        _ b: [String]
    ) -> LCSResult {
        let m = a.count
        let n = b.count

        // Guard against extremely long lines to keep performance bounded.
        guard m > 0, n > 0, m <= 300, n <= 300 else {
            return LCSResult(deletionIndices: [], additionIndices: [])
        }

        // Classic DP table.
        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        for i in 1...m {
            for j in 1...n {
                if a[i - 1] == b[j - 1] {
                    dp[i][j] = dp[i - 1][j - 1] + 1
                } else {
                    dp[i][j] = max(dp[i - 1][j], dp[i][j - 1])
                }
            }
        }

        // Backtrack to find which indices are in the LCS.
        var delIndices = Set<Int>()
        var addIndices = Set<Int>()
        var i = m
        var j = n
        while i > 0 && j > 0 {
            if a[i - 1] == b[j - 1] {
                delIndices.insert(i - 1)
                addIndices.insert(j - 1)
                i -= 1
                j -= 1
            } else if dp[i - 1][j] > dp[i][j - 1] {
                i -= 1
            } else {
                j -= 1
            }
        }
        return LCSResult(deletionIndices: delIndices, additionIndices: addIndices)
    }

    // MARK: AttributedString Builder

    private static func buildAttributed(
        tokens: [String],
        lcsIndices: Set<Int>,
        baseColor: Color,
        highlightColor: Color
    ) -> AttributedString {
        var result = AttributedString()
        for (idx, token) in tokens.enumerated() {
            var part = AttributedString(token)
            let isUnchanged = lcsIndices.contains(idx)
            part.backgroundColor = isUnchanged ? baseColor : highlightColor
            result.append(part)
        }
        return result
    }
}
