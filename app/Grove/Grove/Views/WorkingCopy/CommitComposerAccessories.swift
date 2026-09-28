// Views/WorkingCopy/CommitComposerAccessories.swift
// Grove
//
// Buttons along the bottom of the commit message box: templates and other message helpers.

import SwiftUI

struct CommitComposerAccessories: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @Environment(\.openSettings) private var openSettings
    @State private var isGitmojiShown = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Spacer(minLength: 0)
            gitmojiButton
            templateMenu
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs + 2)
    }

    private var gitmojiButton: some View {
        Button { isGitmojiShown.toggle() } label: { Image(systemName: "face.smiling") }
            .help("Insert Gitmoji (or type : in the summary)")
            .accessibilityLabel("Insert Gitmoji")
            .popover(isPresented: $isGitmojiShown, arrowEdge: .bottom) {
                GitmojiPicker { gitmoji in
                    viewModel.insertGitmoji(gitmoji)
                    isGitmojiShown = false
                }
            }
    }

    private var templateMenu: some View {
        Menu {
            let templates = viewModel.availableTemplates
            if templates.isEmpty {
                Text("No Templates")
            }
            ForEach(templates) { template in
                Button(template.name) { viewModel.applyTemplate(template) }
                if template.id == CommitTemplate.gitTemplateID && templates.count > 1 { Divider() }
            }
            Divider()
            Button("Manage Templates\u{2026}") { PreferencesTab.templates.open(openSettings) }
        } label: {
            Image(systemName: "text.badge.plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Insert Template")
        .accessibilityLabel("Insert Template")
    }
}

#Preview {
    CommitComposerAccessories()
        .environment(WorkingCopyViewModel(repository: MockGitRepository()))
        .frame(width: 320)
        .padding()
        .background(Theme.background)
}
