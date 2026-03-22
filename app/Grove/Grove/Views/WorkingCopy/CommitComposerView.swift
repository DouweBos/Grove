// Views/WorkingCopy/CommitComposerView.swift
// Grove
//
// Commit composer occupying the top-left zone of the Working Copy layout.
// Contains: subject field with character count + autocomplete, optional body,
// Amend checkbox, Sign Off checkbox, profile picker, and the Commit button.
// Inline composer with a prominent subject field.

import SwiftUI
import Foundation

// MARK: - CommitComposerView

/// The commit message composition area in the top-left of ``WorkingCopyView``.
///
/// Consumes ``WorkingCopyViewModel`` from the environment.
struct CommitComposerView: View {

    // MARK: Environment

    @Environment(WorkingCopyViewModel.self) private var viewModel

    // MARK: State

    @State private var showBody: Bool = false
    @FocusState private var subjectFocused: Bool

    // MARK: Constants

    private let subjectCharLimit = 72

    // MARK: Body

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            // Subject row — autocomplete is anchored as an overlay here
            HStack(alignment: .center, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showBody.toggle()
                    }
                } label: {
                    Image(systemName: showBody ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)

                TextField("Commit Subject", text: $vm.commitSubject)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($subjectFocused)
                    .onSubmit {
                        if !viewModel.commitSubject.isEmpty {
                            Task { await viewModel.commit() }
                        }
                    }
                    // Dismiss autocomplete when field loses focus.
                    .onChange(of: subjectFocused) { _, focused in
                        if !focused {
                            viewModel.dismissAutoComplete()
                        }
                    }

                characterCountBadge
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            // Autocomplete popover anchored below the subject row.
            .overlay(alignment: .bottomLeading) {
                if viewModel.isAutoCompleteVisible,
                   let trigger = viewModel.autoCompleteTrigger {
                    CommitAutoCompleteView(
                        trigger: trigger,
                        suggestions: viewModel.autoCompleteSuggestions,
                        onSelect: { viewModel.applyAutoComplete($0) },
                        onDismiss: { viewModel.dismissAutoComplete() }
                    )
                    .offset(x: 20, y: 0)
                    .zIndex(100)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    .animation(.easeOut(duration: 0.12), value: viewModel.isAutoCompleteVisible)
                }
            }

            if showBody {
                Divider()
                TextEditor(text: $vm.commitBody)
                    .font(.system(size: 12))
                    .frame(minHeight: 60, maxHeight: 120)
                    .padding(.horizontal, 6)
                    .overlay(alignment: .topLeading) {
                        if viewModel.commitBody.isEmpty {
                            Text("Detailed description…")
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                        }
                    }
            }

            Divider()

            // Footer
            HStack(spacing: 12) {
                Toggle("Amend", isOn: $vm.isAmend)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))

                Toggle("Sign Off", isOn: $vm.signOff)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))

                if viewModel.isSigningAvailable {
                    Toggle(isOn: $vm.signCommit) {
                        Label("Sign", systemImage: "lock.fill")
                            .font(.system(size: 11))
                    }
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .help("Sign this commit with GPG/SSH key")
                }

                Spacer()

                profilePicker
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            commitButton
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
        }
        .background(.regularMaterial)
    }

    // MARK: Character Count Badge

    private var characterCountBadge: some View {
        let count = viewModel.commitSubject.count
        let isOverLimit = count > subjectCharLimit
        return Text(verbatim: "\(count)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(isOverLimit ? Color.red : Color.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOverLimit ? Color.red.opacity(0.15) : Color.clear)
            )
    }

    // MARK: Profile Picker

    /// A compact `Menu` that lets the user choose which git identity to commit as.
    ///
    /// Shows an avatar initial circle and the selected profile name.  When
    /// multiple profiles are available a popover menu lists all of them.
    @ViewBuilder
    private var profilePicker: some View {
        if viewModel.availableProfiles.count <= 1 {
            // Single profile — show as a plain non-interactive label.
            profileLabel(for: viewModel.selectedProfile)
        } else {
            Menu {
                ForEach(viewModel.availableProfiles) { profile in
                    Button {
                        viewModel.selectProfile(profile)
                    } label: {
                        HStack {
                            Text(profile.name)
                            Text(profile.email)
                                .foregroundStyle(.secondary)
                            if profile.id == viewModel.selectedProfile?.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                profileLabel(for: viewModel.selectedProfile)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    /// Renders the avatar circle + name for any ``UserProfileData``.
    @ViewBuilder
    private func profileLabel(for profile: UserProfileData?) -> some View {
        HStack(spacing: 4) {
            ProfileAvatarView(initial: profile?.initial ?? "?")
            Text(profile?.name ?? "No Profile")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Commit Button

    private var commitButton: some View {
        let canCommit = !viewModel.commitSubject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.stagedFiles.isEmpty

        return Button {
            Task { await viewModel.commit() }
        } label: {
            Text(viewModel.isAmend ? "Amend" : "Commit")
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .disabled(!canCommit)
        .keyboardShortcut(.return, modifiers: .command)
    }
}

// MARK: - ProfileAvatarView

/// A small filled circle displaying the first letter of a profile name.
///
/// Extracted so it can be reused wherever a git identity is displayed.
struct ProfileAvatarView: View {

    let initial: String
    var size: CGFloat = 20

    var body: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.75))
            .frame(width: size, height: size)
            .overlay(
                Text(initial)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
            )
    }
}

// MARK: - Preview

#Preview("Commit Composer — Single Profile") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    CommitComposerView()
        .environment(vm)
        .frame(width: 300)
}

#Preview("Commit Composer — Multiple Profiles") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    vm.loadProfiles(from: [
        UserProfileData(
            id: UUID(),
            name: "Jane Developer",
            email: "jane@example.com",
            signingKeyID: nil,
            isDefault: true
        ),
        UserProfileData(
            id: UUID(),
            name: "Bob Contributor",
            email: "bob@example.com",
            signingKeyID: nil,
            isDefault: false
        )
    ])
    return CommitComposerView()
        .environment(vm)
        .frame(width: 300)
}

#Preview("Commit Composer — Autocomplete Active") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    vm.commitSubject = "fix: closes #"
    return CommitComposerView()
        .environment(vm)
        .frame(width: 300)
        .padding(.bottom, 120) // room for the dropdown
}
