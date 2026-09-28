// DesignSystem/Theme.swift
// Grove
//
// Every color the UI uses. Values live in the asset catalog with light and dark variants.

import SwiftUI

enum Theme {
    static let background = Color(.background)
    static let surface = Color(.surface)
    static let surfaceRaised = Color(.surfaceRaised)
    static let border = Color(.border)
    static let textPrimary = Color(.textPrimary)
    static let textSecondary = Color(.textSecondary)
    static let pillSelected = Color(.pillSelected)
    static let pillSelectedText = Color(.pillSelectedText)
    static let accent = Color.accentColor
    static let success = Color(.success)
    static let warning = Color(.warning)
    static let danger = Color(.danger)
    static let info = Color(.info)

    static let lanePalette: [Color] = [
        Color(.lane1), Color(.lane2), Color(.lane3), Color(.lane4),
        Color(.lane5), Color(.lane6), Color(.lane7), Color(.lane8)
    ]

    static func laneColor(_ index: Int) -> Color {
        lanePalette[abs(index) % lanePalette.count]
    }

    // Git semantics.
    static let added = success
    static let deleted = danger
    static let modified = info
    static let renamed = Color(.lane7)
    static let untracked = textSecondary
    static let conflicted = warning

    // Syntax coloring in diffs.
    static let syntaxKeyword = Color(.syntaxKeyword)
    static let syntaxString = Color(.syntaxString)
    static let syntaxComment = Color(.syntaxComment)
    static let syntaxNumber = Color(.syntaxNumber)
    static let syntaxType = Color(.syntaxType)

    static let addedFill = success.opacity(0.12)
    static let deletedFill = danger.opacity(0.12)
    static let addedWordFill = success.opacity(0.3)
    static let deletedWordFill = danger.opacity(0.3)
    static let hunkHeaderFill = info.opacity(0.08)
    static let selectionFill = accent.opacity(0.16)
    static let subtleFill = textSecondary.opacity(0.12)
    static let bannerFill = warning.opacity(0.14)
    static let dangerFill = danger.opacity(0.12)
    static let successFill = success.opacity(0.12)
    static let track = textSecondary.opacity(0.2)

    enum Radius {
        static let card: CGFloat = 14
        static let tile: CGFloat = 6
        static let pill: CGFloat = 20
        static let row: CGFloat = 10
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }
}

extension Font {
    static let statValue = Font.system(size: 30, weight: .medium, design: .rounded)
    static let statUnit = Font.system(size: 15, weight: .medium, design: .rounded)
    static let pageTitle = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let rowTitle = Font.system(size: 13, weight: .medium)
    static let sectionLabel = Font.system(size: 12, weight: .semibold)
    static let monoCaption = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let monoBody = Font.system(size: 12, weight: .regular, design: .monospaced)
}
