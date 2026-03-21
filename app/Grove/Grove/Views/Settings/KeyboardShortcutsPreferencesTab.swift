// Views/Settings/KeyboardShortcutsPreferencesTab.swift
// Grove
//
// Keyboard shortcuts preferences: view and customize all Grove keyboard shortcuts.

import SwiftUI

// MARK: - ShortcutAction Model

/// A named action with an assignable keyboard shortcut.
struct ShortcutAction: Identifiable {
    let id = UUID()
    let category: ShortcutCategory
    let actionName: String
    let defaultShortcut: ShortcutRepresentation
    var currentShortcut: ShortcutRepresentation

    var isCustomized: Bool { currentShortcut != defaultShortcut }
}

/// A simple keyboard shortcut description for display.
struct ShortcutRepresentation: Equatable {
    let modifiers: EventModifiers
    let keyLabel: String

    static let none = ShortcutRepresentation(modifiers: [], keyLabel: "")

    var displayString: String {
        guard !keyLabel.isEmpty else { return "-" }
        var parts = ""
        if modifiers.contains(.control) { parts += "\u{2303}" }
        if modifiers.contains(.option)  { parts += "\u{2325}" }
        if modifiers.contains(.shift)   { parts += "\u{21E7}" }
        if modifiers.contains(.command) { parts += "\u{2318}" }
        parts += keyLabel
        return parts
    }
}

enum ShortcutCategory: String, CaseIterable, Identifiable {
    case navigation = "Navigation"
    case gitOperations = "Git Operations"
    case view = "View"
    case general = "General"

    var id: String { rawValue }
}

// MARK: - KeyboardShortcutsPreferencesTab

/// Preferences tab for viewing and customizing Grove's keyboard shortcuts.
struct KeyboardShortcutsPreferencesTab: View {

    @State private var actions: [ShortcutAction] = Self.defaultActions()
    @State private var selectedActionID: ShortcutAction.ID?
    @State private var filterCategory: ShortcutCategory? = nil
    @State private var showResetAllConfirmation = false

    private var filteredActions: [ShortcutAction] {
        guard let category = filterCategory else { return actions }
        return actions.filter { $0.category == category }
    }

    var body: some View {
        VStack(spacing: 0) {
            categoryFilter
            Divider()
            shortcutsTable
            Divider()
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "Reset all keyboard shortcuts?",
            isPresented: $showResetAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset All to Defaults", role: .destructive) {
                resetAll()
            }
        } message: {
            Text("All customized shortcuts will be reverted to their factory defaults.")
        }
    }

    // MARK: - Category Filter

    @ViewBuilder
    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                FilterChip(label: "All", isSelected: filterCategory == nil) {
                    filterCategory = nil
                }
                ForEach(ShortcutCategory.allCases) { category in
                    FilterChip(label: category.rawValue, isSelected: filterCategory == category) {
                        filterCategory = (filterCategory == category) ? nil : category
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Shortcuts Table

    @ViewBuilder
    private var shortcutsTable: some View {
        Table(filteredActions, selection: $selectedActionID) {
            TableColumn("Action") { action in
                Text(action.actionName)
                    .foregroundStyle(action.isCustomized ? .orange : .primary)
            }
            .width(min: 160, ideal: 200)

            TableColumn("Shortcut") { action in
                ShortcutCell(action: action) { newShortcut in
                    applyShortcut(newShortcut, to: action.id)
                }
            }
            .width(min: 100, ideal: 120)

            TableColumn("Default") { action in
                Text(action.defaultShortcut.displayString)
                    .foregroundStyle(.secondary)
                    .font(.system(.body, design: .monospaced))
            }
            .width(min: 100, ideal: 120)

            TableColumn("") { action in
                if action.isCustomized {
                    Button("Reset") {
                        resetAction(action.id)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            .width(60)
        }
    }

    // MARK: - Bottom Bar

    @ViewBuilder
    private var bottomBar: some View {
        HStack {
            Spacer()
            Button("Reset All to Defaults") {
                showResetAllConfirmation = true
            }
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func applyShortcut(_ shortcut: ShortcutRepresentation, to id: ShortcutAction.ID) {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return }
        actions[index].currentShortcut = shortcut
    }

    private func resetAction(_ id: ShortcutAction.ID) {
        guard let index = actions.firstIndex(where: { $0.id == id }) else { return }
        actions[index].currentShortcut = actions[index].defaultShortcut
    }

    private func resetAll() {
        for index in actions.indices {
            actions[index].currentShortcut = actions[index].defaultShortcut
        }
    }

    // MARK: - Default Data

    private static func defaultActions() -> [ShortcutAction] {
        [
            // Navigation
            ShortcutAction(category: .navigation, actionName: "Show Repositories", defaultShortcut: .init(modifiers: [.command], keyLabel: "1"), currentShortcut: .init(modifiers: [.command], keyLabel: "1")),
            ShortcutAction(category: .navigation, actionName: "Show Working Copy", defaultShortcut: .init(modifiers: [.command], keyLabel: "2"), currentShortcut: .init(modifiers: [.command], keyLabel: "2")),
            ShortcutAction(category: .navigation, actionName: "Show History", defaultShortcut: .init(modifiers: [.command], keyLabel: "3"), currentShortcut: .init(modifiers: [.command], keyLabel: "3")),
            ShortcutAction(category: .navigation, actionName: "Show Stashes", defaultShortcut: .init(modifiers: [.command], keyLabel: "4"), currentShortcut: .init(modifiers: [.command], keyLabel: "4")),

            // Git Operations
            ShortcutAction(category: .gitOperations, actionName: "Commit", defaultShortcut: .init(modifiers: [.command, .shift], keyLabel: "C"), currentShortcut: .init(modifiers: [.command, .shift], keyLabel: "C")),
            ShortcutAction(category: .gitOperations, actionName: "Fetch", defaultShortcut: .init(modifiers: [.command, .shift], keyLabel: "F"), currentShortcut: .init(modifiers: [.command, .shift], keyLabel: "F")),
            ShortcutAction(category: .gitOperations, actionName: "Pull", defaultShortcut: .init(modifiers: [.command, .shift], keyLabel: "P"), currentShortcut: .init(modifiers: [.command, .shift], keyLabel: "P")),
            ShortcutAction(category: .gitOperations, actionName: "Push", defaultShortcut: .init(modifiers: [.command, .shift], keyLabel: "U"), currentShortcut: .init(modifiers: [.command, .shift], keyLabel: "U")),
            ShortcutAction(category: .gitOperations, actionName: "Create Branch", defaultShortcut: .init(modifiers: [.command, .shift], keyLabel: "B"), currentShortcut: .init(modifiers: [.command, .shift], keyLabel: "B")),
            ShortcutAction(category: .gitOperations, actionName: "Stage All", defaultShortcut: .init(modifiers: [.command, .shift], keyLabel: "A"), currentShortcut: .init(modifiers: [.command, .shift], keyLabel: "A")),
            ShortcutAction(category: .gitOperations, actionName: "Discard All Changes", defaultShortcut: .init(modifiers: [.command, .option, .shift], keyLabel: "R"), currentShortcut: .init(modifiers: [.command, .option, .shift], keyLabel: "R")),

            // View
            ShortcutAction(category: .view, actionName: "Toggle Sidebar", defaultShortcut: .init(modifiers: [.command, .shift], keyLabel: "S"), currentShortcut: .init(modifiers: [.command, .shift], keyLabel: "S")),
            ShortcutAction(category: .view, actionName: "Open in Editor", defaultShortcut: .init(modifiers: [.command, .shift], keyLabel: "E"), currentShortcut: .init(modifiers: [.command, .shift], keyLabel: "E")),
            ShortcutAction(category: .view, actionName: "Open in Terminal", defaultShortcut: .init(modifiers: [.command, .shift], keyLabel: "T"), currentShortcut: .init(modifiers: [.command, .shift], keyLabel: "T")),
            ShortcutAction(category: .view, actionName: "Show in Finder", defaultShortcut: .init(modifiers: [.command, .shift], keyLabel: "R"), currentShortcut: .init(modifiers: [.command, .shift], keyLabel: "R")),

            // General
            ShortcutAction(category: .general, actionName: "Preferences", defaultShortcut: .init(modifiers: [.command], keyLabel: ","), currentShortcut: .init(modifiers: [.command], keyLabel: ",")),
            ShortcutAction(category: .general, actionName: "Clone Repository", defaultShortcut: .init(modifiers: [.command, .shift], keyLabel: "N"), currentShortcut: .init(modifiers: [.command, .shift], keyLabel: "N")),
        ]
    }
}

// MARK: - ShortcutCell

private struct ShortcutCell: View {
    let action: ShortcutAction
    let onUpdate: (ShortcutRepresentation) -> Void

    var body: some View {
        Text(action.currentShortcut.displayString)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(action.isCustomized ? .orange : .primary)
            .help("Click to record a new shortcut (not yet interactive)")
    }
}

// MARK: - FilterChip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    KeyboardShortcutsPreferencesTab()
        .frame(width: 540, height: 440)
}
