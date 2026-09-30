// Domain/CI/ANSIParser.swift
// Grove
//
// Terminal escape sequences in CI logs: SGR colors and bold, italic, underline; everything else is dropped.

import Foundation

/// The eight terminal colors; bright variants, 256-color and truecolor codes fold into them.
nonisolated enum ANSIColor: Int, Hashable, Sendable {
    case black, red, green, yellow, blue, magenta, cyan, white
}

/// A run of text with one style.
nonisolated struct ANSISpan: Hashable, Sendable {
    var text: String
    var color: ANSIColor?
    var isBold = false
    var isItalic = false
    var isUnderlined = false

    var isPlain: Bool { color == nil && !isBold && !isItalic && !isUnderlined }
}

nonisolated enum ANSIParser {

    /// `text` without its escape sequences.
    static func strip(_ text: String) -> String {
        guard text.utf8.contains(0x1B) else { return text }
        return spans(text).map(\.text).joined()
    }

    /// `text` cut into styled runs. Styles don't carry over from earlier lines, as on GitHub.
    static func spans(_ text: String) -> [ANSISpan] {
        guard text.utf8.contains(0x1B) else { return [ANSISpan(text: text)] }
        var spans: [ANSISpan] = []
        var style = ANSISpan(text: "")
        var rest = text[...]
        func emit(_ run: Substring) {
            guard !run.isEmpty else { return }
            var span = style
            span.text = String(run)
            spans.append(span)
        }
        while let escape = rest.firstIndex(of: "\u{1B}") {
            emit(rest[..<escape])
            let (end, codes) = sequence(in: rest, from: escape)
            if let codes { apply(codes, to: &style) }
            rest = rest[end...]
        }
        emit(rest)
        return spans
    }

    /// The index after the escape sequence starting at `escape`, and its codes when it's an SGR (`ESC [ … m`).
    private static func sequence(in text: Substring, from escape: Substring.Index) -> (end: Substring.Index, codes: [Int]?) {
        var index = text.index(after: escape)
        guard index < text.endIndex, text[index] == "[" else { return (index, nil) }
        index = text.index(after: index)
        let start = index
        while index < text.endIndex {
            let character = text[index]
            if character.isLetter {
                let codes = character == "m" ? text[start..<index].split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 } : nil
                return (text.index(after: index), codes)
            }
            index = text.index(after: index)
        }
        return (index, nil)
    }

    private static func apply(_ codes: [Int], to style: inout ANSISpan) {
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0: style = ANSISpan(text: "")
            case 1: style.isBold = true
            case 3: style.isItalic = true
            case 4: style.isUnderlined = true
            case 22: style.isBold = false
            case 23: style.isItalic = false
            case 24: style.isUnderlined = false
            case 30...37: style.color = ANSIColor(rawValue: code - 30)
            case 90...97: style.color = ANSIColor(rawValue: code - 90)
            case 39: style.color = nil
            case 38, 48:
                // Extended colors carry their value in the next codes; backgrounds are skipped but still consumed.
                let (color, used) = extended(codes[(index + 1)...])
                if code == 38 { style.color = color }
                index += used
            default: break
            }
            index += 1
        }
    }

    /// `5;n` (256 colors) or `2;r;g;b` (truecolor) → the nearest of the eight, and how many codes that took.
    private static func extended(_ codes: ArraySlice<Int>) -> (color: ANSIColor?, used: Int) {
        switch codes.first {
        case 5:
            guard let value = codes.dropFirst().first else { return (nil, codes.count) }
            return (quantise(palette: value), 2)
        case 2:
            let rgb = Array(codes.dropFirst().prefix(3))
            guard rgb.count == 3 else { return (nil, codes.count) }
            return (quantise(red: rgb[0], green: rgb[1], blue: rgb[2]), 4)
        default:
            return (nil, 0)
        }
    }

    static func quantise(palette value: Int) -> ANSIColor? {
        switch value {
        case 0...7: return ANSIColor(rawValue: value)
        case 8...15: return ANSIColor(rawValue: value - 8)
        case 16...231:
            let cube = value - 16
            return quantise(red: cube / 36 * 51, green: cube / 6 % 6 * 51, blue: cube % 6 * 51)
        default:
            // The grayscale ramp: dark grays read as dimmed text, light ones as plain.
            return value < 244 ? .black : .white
        }
    }

    /// A channel counts when it's close to the strongest one; near-grays become black or white.
    static func quantise(red: Int, green: Int, blue: Int) -> ANSIColor? {
        let strongest = max(red, green, blue)
        guard strongest - min(red, green, blue) > 40 else { return strongest < 140 ? .black : .white }
        let threshold = Double(strongest) * 0.6
        let bits = (Double(red) >= threshold ? 1 : 0) | (Double(green) >= threshold ? 2 : 0) | (Double(blue) >= threshold ? 4 : 0)
        return ANSIColor(rawValue: bits)
    }
}
