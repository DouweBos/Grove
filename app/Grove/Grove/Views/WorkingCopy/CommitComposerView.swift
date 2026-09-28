// Views/WorkingCopy/CommitComposerView.swift
// Grove
//
// Commit composer card: subject with autocomplete, body, Amend / Sign-off,
// the git identity that will author the commit, and the Commit button.

import SwiftUI

struct CommitComposerView: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel

    private enum Field { case subject, body }
    @FocusState private var focus: Field?

    private let subjectLimit = 72

    var body: some View {
        @Bindable var vm = viewModel

        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(spacing: 0) {
                subjectField(text: $vm.commitSubject)
                Rectangle().fill(Theme.border).frame(height: 0.5)
                bodyEditor(text: $vm.commitBody)
                CommitComposerAccessories()
            }
            .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
            .overlay(alignment: .topLeading) { autoComplete }
            .zIndex(1)

            CommitDraftNotice()
            options
            footer
        }
        .card(padding: Theme.Spacing.md)
    }

    // MARK: Fields

    private func subjectField(text: Binding<String>) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            TextField("Summary", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
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
                    .font(.monoCaption)
                    .foregroundStyle(count > subjectLimit ? Theme.danger : Theme.textSecondary)
                    .help("Keep the summary under \(subjectLimit) characters")
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 2)
    }

    private func bodyEditor(text: Binding<String>) -> some View {
        TextEditor(text: text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.textPrimary)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.never)
            .focused($focus, equals: .body)
            .frame(minHeight: 44, maxHeight: 110)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .overlay(alignment: .topLeading) {
                if viewModel.commitBody.isEmpty {
                    Text("Description")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.Spacing.md + 1)
                        .padding(.vertical, Theme.Spacing.xs + 2)
                        .allowsHitTesting(false)
                }
            }
    }

    @ViewBuilder
    private var autoComplete: some View {
        if viewModel.isAutoCompleteVisible, let trigger = viewModel.autoCompleteTrigger {
            CommitAutoCompleteView(
                trigger: trigger,
                suggestions: viewModel.autoCompleteSuggestions,
                highlightedID: viewModel.autoCompleteHighlight,
                onSelect: { viewModel.applyAutoComplete($0) },
                onHighlight: { viewModel.highlightAutoComplete($0) }
            )
            .offset(y: 40)
            .transition(.opacity)
        }
    }

    // MARK: Options & Footer

    private var options: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Toggle("Amend", isOn: Binding(get: { viewModel.isAmend }, set: { on in Task { await viewModel.setAmend(on) } }))
                .help("Replace the last commit with the staged changes and this message")
            Toggle("Sign Off", isOn: Binding(get: { viewModel.signOff }, set: { viewModel.setSignOff($0) }))
                .help("Add a Signed-off-by trailer")
            if viewModel.isSigningAvailable {
                Toggle("GPG Sign", isOn: Binding(get: { viewModel.signCommit }, set: { viewModel.setSignCommit($0) }))
                    .help("Sign this commit with your configured key")
            }
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .foregroundStyle(Theme.textSecondary)
    }

    private var footer: some View {
        HStack(spacing: Theme.Spacing.sm) {
            CommitIdentityMenu()
            Spacer(minLength: Theme.Spacing.sm)
            Button {
                Task { await viewModel.commit() }
            } label: {
                Text(viewModel.commitButtonTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, Theme.Spacing.xs)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .fixedSize()
            .disabled(!viewModel.canCommit)
            .help("Commit (⌘↩)")
        }
    }
}

#Preview("Commit Composer") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    CommitComposerView()
        .environment(vm)
        .frame(width: 340)
        .padding()
        .background(Theme.background)
        .task { await vm.refresh() }
}
