// Composer/GitCommitComposer.swift
// GroveUIKit
//
// The commit composer card: summary with autocomplete, description, Amend and Sign Off,
// the identity that authors the commit, and Commit.

#if os(macOS)
import GroveKit
import SwiftUI

struct GitCommitComposer: View {
    @Environment(\.gitStyle) private var style
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @Environment(\.workingCopyHost) private var host
    @Environment(\.workingCopySlots) private var slots

    private enum Field { case subject, body }
    @FocusState private var focus: Field?

    static let subjectLimit = 72

    var body: some View {
        @Bindable var vm = viewModel

        VStack(alignment: .leading, spacing: GitMetrics.Spacing.md) {
            VStack(spacing: 0) {
                subjectField(text: $vm.commitSubject)
                Rectangle().fill(style.border).frame(height: 0.5)
                bodyEditor(text: $vm.commitBody)
                ComposerAccessories { focus = .subject }
            }
            .background(style.background, in: RoundedRectangle(cornerRadius: GitMetrics.Radius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: GitMetrics.Radius.tile, style: .continuous).strokeBorder(style.border, lineWidth: 0.5))
            .overlay(alignment: .topLeading) { autoComplete }
            .zIndex(1)

            options
            footer
        }
        .gitCard(padding: GitMetrics.Spacing.md)
        .onChange(of: focus != nil) { _, focused in host.onMessageFocus?(focused) }
        .onDisappear { host.onMessageFocus?(false) }
    }

    // MARK: Fields

    private func subjectField(text: Binding<String>) -> some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            TextField("Summary", text: text)
                .textFieldStyle(.plain)
                .font(style.font(13, .medium))
                .foregroundStyle(style.textPrimary)
                .focused($focus, equals: .subject)
                .onSubmit { focus = .body }
                .onKeyPress(.return) { viewModel.acceptAutoComplete() ? .handled : .ignored }
                .onKeyPress(.tab) { viewModel.acceptAutoComplete() ? .handled : .ignored }
                .onKeyPress(.escape) {
                    guard viewModel.isAutoCompleteVisible else { return .ignored }
                    viewModel.dismissAutoComplete()
                    return .handled
                }
                .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                    guard viewModel.isAutoCompleteVisible else { return .ignored }
                    viewModel.moveAutoCompleteHighlight(by: press.key == .upArrow ? -1 : 1)
                    return .handled
                }
                .onChange(of: focus) { _, field in
                    if field != .subject { viewModel.dismissAutoComplete() }
                }
            let count = viewModel.commitSubject.count
            if count > 0 {
                Text("\(count)")
                    .font(style.monoCaption)
                    .foregroundStyle(count > Self.subjectLimit ? style.danger : style.textSecondary)
                    .help("Keep the summary under \(Self.subjectLimit) characters")
            }
        }
        .padding(.horizontal, GitMetrics.Spacing.md)
        .padding(.vertical, GitMetrics.Spacing.sm + 2)
    }

    private func bodyEditor(text: Binding<String>) -> some View {
        TextEditor(text: text)
            .font(style.font(13))
            .foregroundStyle(style.textPrimary)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .focused($focus, equals: .body)
            .frame(minHeight: 44 * style.fontScale, maxHeight: 110 * style.fontScale)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, GitMetrics.Spacing.sm)
            .padding(.vertical, GitMetrics.Spacing.xs + 2)
            .overlay(alignment: .topLeading) {
                if viewModel.commitBody.isEmpty {
                    Text("Description")
                        .font(style.font(13))
                        .foregroundStyle(style.textSecondary)
                        .padding(.horizontal, GitMetrics.Spacing.md + 1)
                        .padding(.vertical, GitMetrics.Spacing.xs + 2)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private var autoComplete: some View {
        if viewModel.isAutoCompleteVisible, let trigger = viewModel.autoCompleteTrigger {
            CommitAutoComplete(
                trigger: trigger,
                suggestions: viewModel.autoCompleteSuggestions,
                highlightedID: viewModel.autoCompleteHighlight,
                onSelect: { suggestion in
                    viewModel.applyAutoComplete(suggestion)
                    reportInsertion(trigger)
                },
                onHighlight: { viewModel.highlightAutoComplete($0) })
            .offset(y: 40 * style.fontScale)
            .transition(.opacity)
        }
    }

    private func reportInsertion(_ trigger: AutoCompleteTrigger) {
        switch trigger {
        case .gitmoji: host.onEvent?(.gitmojiInserted)
        case .template: host.onEvent?(.templateInserted)
        case .issue, .commit, .filename: break
        }
    }

    // MARK: Options & Footer

    private var options: some View {
        HStack(spacing: GitMetrics.Spacing.lg) {
            Toggle("Amend", isOn: Binding(get: { viewModel.isAmend }, set: { on in Task { await viewModel.setAmend(on) } }))
                .help("Replace the last commit with the staged changes and this message")
            Toggle("Sign Off", isOn: Binding(get: { viewModel.signOff }, set: { viewModel.setSignOff($0) }))
                .help("Add a Signed-off-by trailer")
            if viewModel.isSigningAvailable {
                Toggle("Sign", isOn: Binding(get: { viewModel.signCommit }, set: { viewModel.setSignCommit($0) }))
                    .help("Sign this commit with your configured key")
            }
            // The app's own, here rather than beside Commit, so the identity keeps its room.
            if let accessory = slots.composerAccessory {
                Spacer(minLength: GitMetrics.Spacing.sm)
                HStack(spacing: GitMetrics.Spacing.sm) { accessory }.controlSize(.small).fixedSize()
            }
        }
        .toggleStyle(.checkbox)
        .gitClickable()
        .font(style.font(12))
        .foregroundStyle(style.textSecondary)
    }

    private var footer: some View {
        HStack(spacing: GitMetrics.Spacing.sm) {
            CommitIdentityMenu()
            Spacer(minLength: GitMetrics.Spacing.sm)
            Button {
                viewModel.act { await viewModel.commit() }
            } label: {
                Text(viewModel.commitButtonTitle)
                    .font(style.font(13, .semibold))
                    .padding(.horizontal, GitMetrics.Spacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .fixedSize()
            .disabled(!viewModel.canCommit)
            .help(viewModel.commitBlocker ?? "Commit (\u{2318}\u{21A9})")
        }
    }
}

#Preview("Commit Composer") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    GitCommitComposer()
        .environment(vm)
        .frame(width: 340)
        .padding()
        .task { await vm.refresh() }
}
#endif
