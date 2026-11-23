// Composer/ComposerAccessories.swift
// GroveUIKit
//
// Buttons along the bottom of the message box: gitmoji and templates.

#if os(macOS)
import GroveKit
import SwiftUI

struct ComposerAccessories: View {
    @Environment(\.gitStyle) private var style
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @Environment(\.workingCopyHost) private var host
    @State private var isGitmojiShown = false
    /// Puts the caret back in the summary after an insertion.
    let focusSubject: () -> Void

    var body: some View {
        HStack(spacing: GitMetrics.Spacing.md) {
            Spacer(minLength: 0)
            gitmojiButton
            templateMenu
        }
        .buttonStyle(.borderless)
        .font(style.font(13))
        .foregroundStyle(style.textSecondary)
        .padding(.horizontal, GitMetrics.Spacing.sm)
        .padding(.bottom, GitMetrics.Spacing.xs + 2)
    }

    private var gitmojiButton: some View {
        Button { isGitmojiShown.toggle() } label: { Image(systemName: "face.smiling") }
            .gitClickable()
            .help("Insert Gitmoji (or type : in the summary)")
            .accessibilityLabel("Insert Gitmoji")
            .popover(isPresented: $isGitmojiShown, arrowEdge: .bottom) {
                GitmojiPicker { gitmoji in
                    viewModel.insertGitmoji(gitmoji)
                    isGitmojiShown = false
                    host.onEvent?(.gitmojiInserted)
                    focusSubject()
                }
                .environment(\.gitStyle, style)
            }
    }

    private var templateMenu: some View {
        Menu {
            let templates = viewModel.availableTemplates
            if templates.isEmpty {
                Text("No Templates")
            }
            ForEach(templates) { template in
                Button(template.name) {
                    viewModel.applyTemplate(template)
                    host.onEvent?(.templateInserted)
                }
                if template.id == CommitTemplate.gitTemplateID && templates.count > 1 { Divider() }
            }
            if let manage = host.manageTemplates {
                Divider()
                Button("Manage Templates", action: manage)
            }
        } label: {
            Image(systemName: "text.badge.plus")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .gitClickable()
        .help("Insert Template (or type / in the summary)")
        .accessibilityLabel("Insert Template")
    }
}
#endif
