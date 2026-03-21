// Views/Reflog/ReflogDetailPanel.swift
// Grove

import SwiftUI

// MARK: - ReflogDetailPanel

/// The right panel of the Reflog view — shows details for the selected entry.
///
/// Displays the action description, the referenced commit info (SHA, author,
/// message, date), and provides "Reset HEAD" and "Create Branch" actions.
struct ReflogDetailPanel: View {

    @Environment(ReflogViewModel.self) private var viewModel

    // MARK: - Sheet State

    @State private var isCreateBranchPresented = false
    @State private var newBranchName = ""

    // MARK: - Body

    var body: some View {
        if let entry = viewModel.selectedEntry {
            VStack(alignment: .leading, spacing: 0) {
                entryHeader(entry)
                Divider()
                commitDetail(entry)
            }
        } else {
            emptyState
        }
    }

    // MARK: - Entry Header

    @ViewBuilder
    private func entryHeader(_ entry: ReflogEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Action buttons row
            HStack(spacing: 8) {
                Menu("Restore\u{2026}") {
                    Button("Mixed Reset (keep working tree)") {
                        Task { await viewModel.resetToEntry(entry, mode: .mixed) }
                    }
                    Button("Soft Reset (keep staged)") {
                        Task { await viewModel.resetToEntry(entry, mode: .soft) }
                    }
                    Divider()
                    Button("Hard Reset (discard all changes)", role: .destructive) {
                        Task { await viewModel.resetToEntry(entry, mode: .hard) }
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Create Branch\u{2026}") {
                    newBranchName = ""
                    isCreateBranchPresented = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.newSHA, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Copy commit SHA")
            }

            // Entry summary card
            VStack(alignment: .leading, spacing: 6) {
                let idx = viewModel.index(of: entry)
                let actionType = viewModel.actionType(for: entry)

                HStack(spacing: 6) {
                    Image(systemName: actionType.systemImage)
                        .foregroundStyle(actionColor(actionType))
                    Text("HEAD@{\(idx)}")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .fontDesign(.monospaced)
                    Text(actionType.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(actionColor(actionType))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(actionColor(actionType).opacity(0.12), in: Capsule())
                }

                Text(entry.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                HStack(spacing: 10) {
                    Label(entry.committerName, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(entry.date.formatted(.dateTime.year().month().day().hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(10)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(12)
        .sheet(isPresented: $isCreateBranchPresented) {
            createBranchSheet(entry)
        }
    }

    // MARK: - Commit Detail

    @ViewBuilder
    private func commitDetail(_ entry: ReflogEntry) -> some View {
        if viewModel.isLoadingDetail {
            VStack {
                Spacer()
                ProgressView("Loading commit\u{2026}")
                Spacer()
            }
        } else if let commit = viewModel.selectedCommit {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Referenced Commit")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    commitInfoCard(commit)
                        .padding(.horizontal, 12)

                    Spacer(minLength: 12)
                }
            }
        } else {
            // Entry exists but commit could not be resolved (e.g. after GC)
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
                Text("Commit no longer available")
                    .foregroundStyle(.secondary)
                Text(String(entry.newSHA.prefix(7)))
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Commit Info Card

    @ViewBuilder
    private func commitInfoCard(_ commit: CommitInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // SHA row
            HStack(spacing: 4) {
                Text("SHA:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(commit.id)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Divider()

            // Author
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(commit.authorName)
                        .fontWeight(.medium)
                    Text(commit.authorEmail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(commit.authorDate.formatted(.dateTime.year().month().day().hour().minute()))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Commit message
            VStack(alignment: .leading, spacing: 4) {
                Text(commit.summary)
                    .fontWeight(.medium)
                    .textSelection(.enabled)

                if let body = commit.body, !body.isEmpty {
                    Text(body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            if commit.isSigned {
                Label("Verified signature", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Create Branch Sheet

    @ViewBuilder
    private func createBranchSheet(_ entry: ReflogEntry) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create Branch")
                .font(.headline)

            Text("Create a new branch at HEAD@{\(viewModel.index(of: entry))} (\(String(entry.newSHA.prefix(7)))).")
                .font(.callout)
                .foregroundStyle(.secondary)

            TextField("Branch name", text: $newBranchName)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    isCreateBranchPresented = false
                }
                .keyboardShortcut(.escape)

                Button("Create") {
                    let name = newBranchName.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { return }
                    isCreateBranchPresented = false
                    Task { await viewModel.createBranch(name: name, from: entry) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newBranchName.trimmingCharacters(in: .whitespaces).isEmpty)
                .keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 340)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Select a reflog entry to view details")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func actionColor(_ type: ReflogActionType) -> Color {
        switch type {
        case .commit, .commitAmend:     return .green
        case .checkout:                  return .blue
        case .rebase:                    return .orange
        case .merge:                     return .purple
        case .pull:                      return .cyan
        case .push:                      return .teal
        case .reset:                     return .red
        case .cherryPick:                return .pink
        case .other:                     return .secondary
        }
    }
}

// MARK: - Preview

#Preview {
    let vm = ReflogViewModel(repository: MockGitRepository())
    vm.selectedEntry = MockData.reflogEntries[0]
    vm.selectedCommit = MockData.commits[0]

    return ReflogDetailPanel()
        .environment(vm)
        .frame(width: 420, height: 500)
}
