// Views/WorkingCopy/CommitComposerView.swift
// Grove
//
// Commit composer occupying the top-left zone of the Working Copy layout.
// Contains: subject field with character count, optional body, Amend checkbox,
// Sign Off checkbox, profile selector, and the Commit button.
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
            // Subject row
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

                characterCountBadge
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

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

                Spacer()

                profileLabel
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

    // MARK: Profile Label

    private var profileLabel: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 20, height: 20)
                .overlay(
                    Text(viewModel.repository.displayName.prefix(1).uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                )
            Text(viewModel.repository.displayName)
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

// MARK: - Preview

#Preview("Commit Composer") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    CommitComposerView()
        .environment(vm)
        .frame(width: 300)
}
