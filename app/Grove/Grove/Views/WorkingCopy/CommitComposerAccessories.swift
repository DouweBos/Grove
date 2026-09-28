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
            draftButton
            Spacer(minLength: 0)
            gitmojiButton
            templateMenu
        }
        .buttonStyle(.borderless)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs + 2)
    }

    @ViewBuilder
    private var draftButton: some View {
        if viewModel.aiDraft.isDrafting {
            HStack(spacing: Theme.Spacing.xs) {
                ProgressView().controlSize(.small)
                Text("Drafting\u{2026}").font(.system(size: 12))
            }
        } else {
            Button { Task { await viewModel.draftCommitMessage() } } label: {
                Label("Draft", systemImage: "sparkles").font(.system(size: 12))
            }
            .disabled(!viewModel.canDraftMessage && viewModel.hasAnthropicKey)
            .help(draftHelp)
        }
    }

    private var draftHelp: String {
        if !viewModel.hasAnthropicKey { return "Draft a commit message with Claude; needs an Anthropic API key" }
        return viewModel.stagedFiles.isEmpty
            ? "Stage changes to draft a message from them"
            : "Draft the summary and description from the staged diff with Claude. Sends the staged diff to Anthropic."
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

/// Draft progress problems under the message box: a missing API key or a failed request.
struct CommitDraftNotice: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if viewModel.aiDraft.needsKey {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label("Add an Anthropic API key to draft with Claude", systemImage: "key")
                    .font(.system(size: 12, weight: .semibold))
                Text("Create one at console.anthropic.com and paste it in Preferences \u{203A} Accounts. "
                     + "It\u{2019}s kept in your Keychain; the staged diff is only sent when you click Draft.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Open Accounts\u{2026}") { PreferencesTab.accounts.open(openSettings) }
                    Button("Not Now") { viewModel.dismissDraftError() }
                }
                .controlSize(.small)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.bannerFill, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
        } else if let error = viewModel.aiDraft.errorMessage {
            Banner(symbol: "exclamationmark.triangle", message: error, tone: .negative,
                   onDismiss: { viewModel.dismissDraftError() })
        }
    }
}

#Preview {
    CommitComposerAccessories()
        .environment(WorkingCopyViewModel(repository: MockGitRepository()))
        .frame(width: 320)
        .padding()
        .background(Theme.background)
}
