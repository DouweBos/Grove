// Diff/Engine/DiffWrap.swift
// GroveUIKit
//
// Where a line wraps, by columns. The same breaks size the row and draw it, so they can't disagree.

#if os(macOS)
import Foundation

nonisolated enum DiffWrap {

    /// The display text's UTF-16 offsets where each visual line starts; always at least one.
    static func starts(_ content: String, columns: Int) -> [Int] {
        var scan = Scan(columns: max(columns, 1))
        var text = content
        let isASCII = text.withUTF8 { bytes in
            if bytes.count <= scan.columns, bytes.allSatisfy({ $0 < 0x80 && $0 != 0x09 }) { return true }
            guard bytes.allSatisfy({ $0 < 0x80 }) else { return false }
            for byte in bytes {
                if byte == 0x09 {
                    scan.add(cells: DiffLineText.tab.count, units: DiffLineText.tab.count, isSpace: true)
                } else {
                    scan.add(cells: 1, units: 1, isSpace: byte == 0x20)
                }
            }
            return true
        }
        if !isASCII {
            for character in content {
                var units = 0
                for unit in character.utf16 { units += unit == 0x09 ? DiffLineText.tab.count : 1 }
                let cells = character == "\t" ? DiffLineText.tab.count : cells(of: character)
                scan.add(cells: cells, units: units, isSpace: character == " " || character == "\t")
            }
        }
        return scan.starts
    }

    static func lineCount(_ content: String, columns: Int) -> Int {
        starts(content, columns: columns).count
    }

    /// A row height for a line not measured yet, without reading it.
    static func estimatedLineCount(_ content: String, columns: Int) -> Int {
        max(1, (content.utf8.count + max(columns, 1) - 1) / max(columns, 1))
    }

    /// Fallback fonts draw these wider than a monospaced cell; rounded up so a wrapped line never clips.
    private static func cells(of character: Character) -> Int {
        guard let scalar = character.unicodeScalars.first?.value else { return 1 }
        if scalar >= 0x1F000 { return 3 }
        switch scalar {
        case 0x1100...0x115F, 0x2600...0x27BF, 0x2E80...0xA4CF, 0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFF00...0xFF60: return 2
        default: return 1
        }
    }

    private struct Scan {
        let columns: Int
        private(set) var starts = [0]
        private var width = 0
        private var offset = 0
        private var hasWord = false
        /// After the last space that follows a word: where to break, and the width up to it.
        private var candidate: (offset: Int, width: Int)?

        init(columns: Int) {
            self.columns = columns
        }

        mutating func add(cells: Int, units: Int, isSpace: Bool) {
            // Spaces hang past the edge; the word after them starts the next line.
            if !isSpace, width > 0, width + cells > columns {
                if let candidate, candidate.offset < offset {
                    starts.append(candidate.offset)
                    width -= candidate.width
                } else {
                    starts.append(offset)
                    width = 0
                }
                candidate = nil
                if width > 0, width + cells > columns {
                    starts.append(offset)
                    width = 0
                }
            }
            width += cells
            offset += units
            if isSpace {
                if hasWord { candidate = (offset, width) }
            } else {
                hasWord = true
            }
        }
    }
}
#endif
