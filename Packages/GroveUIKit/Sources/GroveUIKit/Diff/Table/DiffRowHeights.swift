// Diff/Table/DiffRowHeights.swift
// GroveUIKit
//
// Wrapped rows are measured as the table asks. A long burst of asking gets estimates, put right
// when such a row comes into view.

#if os(macOS)
import Foundation

struct DiffRowHeights {
    /// How many rows one run-loop turn measures; AppKit may ask about every row at once.
    static let measuredPerTurn = 2_000

    private var measured: [Int: Int] = [:]
    private var estimated = IndexSet()
    private(set) var measuredThisTurn = 0
    /// Rows shown since they were estimated, whose height the table has to ask again.
    private(set) var corrected = IndexSet()

    mutating func reset() {
        measured = [:]
        estimated = IndexSet()
        corrected = IndexSet()
        measuredThisTurn = 0
    }

    mutating func startTurn() {
        measuredThisTurn = 0
    }

    mutating func takeCorrected() -> IndexSet {
        defer { corrected = IndexSet() }
        return corrected
    }

    /// The row's visual lines, exact until this turn's budget is spent.
    mutating func lineCount(row: Int, measure: () -> Int, estimate: () -> Int) -> Int {
        if let known = measured[row] { return known }
        guard measuredThisTurn < Self.measuredPerTurn else {
            estimated.insert(row)
            return estimate()
        }
        measuredThisTurn += 1
        let count = measure()
        measured[row] = count
        return count
    }

    /// Whether a row coming into view needs its height asked again.
    mutating func willShow(row: Int, measure: () -> Int) -> Bool {
        guard !estimated.isEmpty, estimated.contains(row) else { return false }
        estimated.remove(row)
        measured[row] = measure()
        corrected.insert(row)
        return true
    }
}
#endif
