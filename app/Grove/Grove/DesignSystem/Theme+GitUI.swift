// DesignSystem/Theme+GitUI.swift
// Grove
//
// Grove's asset catalog as GroveUIKit's style.

import GroveUIKit
import SwiftUI

extension Theme {
    static let gitUI = GitUIStyle(
        background: background, surface: surface, surfaceRaised: surfaceRaised, border: border,
        textPrimary: textPrimary, textSecondary: textSecondary, accent: accent,
        pillSelected: pillSelected, pillSelectedText: pillSelectedText,
        success: success, warning: warning, danger: danger, info: info, renamed: renamed, lanes: lanePalette,
        syntax: GitUIStyle.Syntax(keyword: syntaxKeyword, string: syntaxString, comment: syntaxComment,
                                  number: syntaxNumber, type: syntaxType))
}
