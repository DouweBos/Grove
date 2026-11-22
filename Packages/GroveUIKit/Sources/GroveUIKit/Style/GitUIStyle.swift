// Style/GitUIStyle.swift
// GroveUIKit
//
// What the host app decides about the look. Spacing and radii are the kit's.

#if os(macOS)
import SwiftUI

public nonisolated struct GitUIStyle: Equatable, Sendable {

    public nonisolated struct Syntax: Equatable, Sendable {
        public var keyword: Color
        public var string: Color
        public var comment: Color
        public var number: Color
        public var type: Color

        public init(keyword: Color, string: Color, comment: Color, number: Color, type: Color) {
            self.keyword = keyword
            self.string = string
            self.comment = comment
            self.number = number
            self.type = type
        }
    }

    public var background: Color
    public var surface: Color
    public var surfaceRaised: Color
    public var border: Color
    public var textPrimary: Color
    public var textSecondary: Color
    public var accent: Color
    public var pillSelected: Color
    public var pillSelectedText: Color
    public var success: Color
    public var warning: Color
    public var danger: Color
    public var info: Color
    public var renamed: Color
    public var lanes: [Color]
    public var syntax: Syntax
    /// The host's text zoom; every font and text-bound metric multiplies by it.
    public var fontScale: CGFloat
    /// Whether clickable things show the pointing hand.
    public var showsPointingHand: Bool

    public init(background: Color, surface: Color, surfaceRaised: Color, border: Color, textPrimary: Color,
                textSecondary: Color, accent: Color, pillSelected: Color, pillSelectedText: Color, success: Color,
                warning: Color, danger: Color, info: Color, renamed: Color, lanes: [Color], syntax: Syntax,
                fontScale: CGFloat = 1, showsPointingHand: Bool = false) {
        self.background = background
        self.surface = surface
        self.surfaceRaised = surfaceRaised
        self.border = border
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.accent = accent
        self.pillSelected = pillSelected
        self.pillSelectedText = pillSelectedText
        self.success = success
        self.warning = warning
        self.danger = danger
        self.info = info
        self.renamed = renamed
        self.lanes = lanes
        self.syntax = syntax
        self.fontScale = fontScale
        self.showsPointingHand = showsPointingHand
    }

    /// System colours, for previews and an app that hasn't set a style.
    public static let system = GitUIStyle(
        background: Color(nsColor: .windowBackgroundColor), surface: Color(nsColor: .controlBackgroundColor),
        surfaceRaised: Color(nsColor: .underPageBackgroundColor), border: Color(nsColor: .separatorColor),
        textPrimary: .primary, textSecondary: .secondary, accent: .accentColor,
        pillSelected: .primary, pillSelectedText: Color(nsColor: .windowBackgroundColor),
        success: .green, warning: .orange, danger: .red, info: .blue, renamed: .purple,
        lanes: [.blue, .green, .orange, .purple, .pink, .teal, .yellow, .red],
        syntax: Syntax(keyword: .purple, string: .green, comment: .secondary, number: .orange, type: .teal))

    func lane(_ index: Int) -> Color {
        lanes.isEmpty ? textSecondary : lanes[abs(index) % lanes.count]
    }

    var subtleFill: Color { textSecondary.opacity(0.12) }
    var selectionFill: Color { accent.opacity(0.16) }
    var track: Color { textSecondary.opacity(0.2) }
    var warningFill: Color { warning.opacity(0.14) }
    var dangerFill: Color { danger.opacity(0.12) }
    var successFill: Color { success.opacity(0.12) }
    var addedWordFill: Color { success.opacity(0.3) }
    var deletedWordFill: Color { danger.opacity(0.3) }
    var hunkHeaderFill: Color { info.opacity(0.08) }

    func font(_ size: CGFloat, _ weight: Font.Weight = .regular, _ design: Font.Design = .default) -> Font {
        .system(size: size * fontScale, weight: weight, design: design)
    }

    var monoCaption: Font { font(12, .regular, .monospaced) }
    var sectionLabel: Font { font(12, .semibold) }
}

enum GitMetrics {
    enum Radius {
        static let card: CGFloat = 14
        static let tile: CGFloat = 6
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
#endif
