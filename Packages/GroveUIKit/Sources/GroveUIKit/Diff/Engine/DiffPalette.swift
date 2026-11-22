// Diff/Engine/DiffPalette.swift
// GroveUIKit
//
// The style's colors for AppKit drawing. They stay dynamic, so they resolve in the appearance they draw in.

#if os(macOS)
import AppKit
import SwiftUI

struct DiffPalette {
    let text: NSColor
    let secondary: NSColor
    let added: NSColor
    let removed: NSColor
    let addedFill: NSColor
    let removedFill: NSColor
    let addedWord: NSColor
    let removedWord: NSColor
    let headerFill: NSColor
    let emptySide: NSColor
    let divider: NSColor
    let accent: NSColor
    let onAccent: NSColor
    let selection: NSColor
    let button: NSColor
    let dangerFill: NSColor
    let showsPointingHand: Bool
    private let keyword: NSColor
    private let string: NSColor
    private let comment: NSColor
    private let number: NSColor
    private let type: NSColor

    init(_ style: GitUIStyle) {
        text = NSColor(style.textPrimary)
        secondary = NSColor(style.textSecondary)
        added = NSColor(style.success)
        removed = NSColor(style.danger)
        addedFill = NSColor(style.successFill)
        removedFill = NSColor(style.dangerFill)
        addedWord = NSColor(style.addedWordFill)
        removedWord = NSColor(style.deletedWordFill)
        headerFill = NSColor(style.hunkHeaderFill)
        emptySide = NSColor(style.subtleFill)
        divider = NSColor(style.border)
        accent = NSColor(style.accent)
        onAccent = NSColor(style.pillSelectedText)
        selection = NSColor(style.selectionFill)
        button = NSColor(style.surface)
        dangerFill = NSColor(style.dangerFill)
        showsPointingHand = style.showsPointingHand
        keyword = NSColor(style.syntax.keyword)
        string = NSColor(style.syntax.string)
        comment = NSColor(style.syntax.comment)
        number = NSColor(style.syntax.number)
        type = NSColor(style.syntax.type)
    }

    func color(_ kind: SyntaxKind) -> NSColor {
        switch kind {
        case .keyword: keyword
        case .string: string
        case .comment: comment
        case .number: number
        case .type: type
        }
    }
}
#endif
