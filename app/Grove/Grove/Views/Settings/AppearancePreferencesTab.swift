// Views/Settings/AppearancePreferencesTab.swift
// Grove
//
// Appearance preferences: theme, accent color, code font, diff display options.

import SwiftUI

// MARK: - AppearancePreferencesTab

/// Appearance preferences tab for controlling Grove's visual style.
struct AppearancePreferencesTab: View {

    // MARK: - Theme

    @State private var theme: AppTheme = .system
    @State private var accentColor: Color = .orange

    // MARK: - Code / Diff Font

    @State private var codeFontFamily: CodeFontFamily = .sfMono
    @State private var codeFontSize: CodeFontSize = .medium

    // MARK: - Diff Display

    @State private var showLineNumbers = true
    @State private var tabWidth: TabWidth = .four
    @State private var wordWrap = false
    @State private var compactSidebar = false

    var body: some View {
        Form {
            themeSection
            fontSection
            diffSection
            layoutSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Theme Section

    @ViewBuilder
    private var themeSection: some View {
        Section("Theme") {
            LabeledContent("Appearance") {
                Picker("", selection: $theme) {
                    ForEach(AppTheme.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            LabeledContent("Accent color") {
                ColorPicker("", selection: $accentColor, supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Font Section

    @ViewBuilder
    private var fontSection: some View {
        Section("Code Font") {
            LabeledContent("Font family") {
                Picker("", selection: $codeFontFamily) {
                    ForEach(CodeFontFamily.allCases) { family in
                        Text(family.label).tag(family)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)
            }

            LabeledContent("Font size") {
                Picker("", selection: $codeFontSize) {
                    ForEach(CodeFontSize.allCases) { size in
                        Text(size.label).tag(size)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }
        }
    }

    // MARK: - Diff Section

    @ViewBuilder
    private var diffSection: some View {
        Section("Diff Display") {
            Toggle("Show line numbers", isOn: $showLineNumbers)

            LabeledContent("Tab width") {
                Picker("", selection: $tabWidth) {
                    ForEach(TabWidth.allCases) { width in
                        Text(width.label).tag(width)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }

            Toggle("Word wrap", isOn: $wordWrap)
        }
    }

    // MARK: - Layout Section

    @ViewBuilder
    private var layoutSection: some View {
        Section("Layout") {
            Toggle("Compact sidebar mode", isOn: $compactSidebar)
        }
    }
}

// MARK: - Supporting Types

extension AppearancePreferencesTab {

    enum AppTheme: String, CaseIterable, Identifiable {
        case light, dark, system

        var id: String { rawValue }

        var label: String {
            switch self {
            case .light: return "Light"
            case .dark: return "Dark"
            case .system: return "System"
            }
        }
    }

    enum CodeFontFamily: String, CaseIterable, Identifiable {
        case sfMono = "SF Mono"
        case menlo = "Menlo"
        case monaco = "Monaco"
        case firaCode = "Fira Code"

        var id: String { rawValue }

        var label: String { rawValue }
    }

    enum CodeFontSize: String, CaseIterable, Identifiable {
        case small, medium, large

        var id: String { rawValue }

        var label: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            }
        }
    }

    enum TabWidth: Int, CaseIterable, Identifiable {
        case two = 2
        case four = 4
        case eight = 8

        var id: Int { rawValue }

        var label: String { "\(rawValue)" }
    }
}

// MARK: - Preview

#Preview {
    AppearancePreferencesTab()
        .frame(width: 540, height: 440)
}
