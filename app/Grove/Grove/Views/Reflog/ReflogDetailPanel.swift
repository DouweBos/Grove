// Views/Reflog/ReflogDetailPanel.swift
// Grove

import GroveKit
import SwiftUI

/// Detail card for the selected reflog entry: what happened, the commit it points at, restore actions.
struct ReflogDetailPanel: View {

    @Environment(ReflogViewModel.self) private var viewModel

    var body: some View {
        Group {
            if let entry = viewModel.selectedEntry {
                VStack(spacing: 0) {
                    header(entry)
                    Rectangle().fill(Theme.border).frame(height: 0.5)
                    ScrollView {
                        commitSection(entry)
                            .padding(Theme.Spacing.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                EmptyStateView(systemImage: "clock.arrow.circlepath", title: "No Entry Selected",
                               subtitle: "Select a reflog entry to inspect it or restore HEAD to that point.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .panel()
    }

    // MARK: - Header

    private func header(_ entry: ReflogEntry) -> some View {
        let action = viewModel.actionType(for: entry)
        return HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text("HEAD@{\(viewModel.index(of: entry))}")
                        .font(.system(size: 17, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                    Label(action.displayName, systemImage: action.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(action.color)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 3)
                        .background(action.color.opacity(0.14), in: Capsule())
                }
                Text(entry.message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                HStack(spacing: Theme.Spacing.md) {
                    Text("\(entry.oldSHA.prefix(7)) \u{2192} \(entry.newSHA.prefix(7))")
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened)).lineLimit(1)
                }
                .font(.monoCaption)
                .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Theme.Spacing.md)
            HStack(spacing: Theme.Spacing.sm) {
                Button("Create Branch\u{2026}") { viewModel.beginCreateBranch(from: entry) }
                Menu("Reset HEAD") {
                    Button("Soft \u{2014} keep index and files\u{2026}") { viewModel.requestReset(to: entry, mode: .soft) }
                    Button("Mixed \u{2014} keep files\u{2026}") { viewModel.requestReset(to: entry, mode: .mixed) }
                    Divider()
                    Button("Hard \u{2014} discard all changes\u{2026}", role: .destructive) {
                        viewModel.requestReset(to: entry, mode: .hard)
                    }
                }
                .fixedSize()
            }
        }
        .padding(Theme.Spacing.lg)
    }

    // MARK: - Commit

    @ViewBuilder
    private func commitSection(_ entry: ReflogEntry) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionLabel(title: "Commit")
            if viewModel.isLoadingDetail {
                ProgressView().controlSize(.small)
            } else if let commit = viewModel.selectedCommit {
                commitCard(commit)
            } else {
                Banner(symbol: "questionmark.circle",
                       message: "Commit \(entry.newSHA.prefix(7)) is no longer in the object database.")
            }
        }
    }

    private func commitCard(_ commit: CommitInfo) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(commit.summary)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .textSelection(.enabled)
                if let body = commit.body, !body.isEmpty {
                    Text(body)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.lg, verticalSpacing: Theme.Spacing.xs) {
                GridRow {
                    Text("Author").foregroundStyle(Theme.textSecondary)
                    Text("\(commit.authorName) <\(commit.authorEmail)>").textSelection(.enabled)
                }
                GridRow {
                    Text("Date").foregroundStyle(Theme.textSecondary)
                    Text(commit.authorDate.formatted(date: .long, time: .shortened))
                }
                GridRow {
                    Text("SHA").foregroundStyle(Theme.textSecondary)
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(commit.id).font(.monoCaption).textSelection(.enabled).lineLimit(1)
                        CopyButton(value: commit.id, help: "Copy SHA", confirmation: "Copied SHA")
                    }
                }
                if commit.isSigned {
                    GridRow {
                        Text("Signature").foregroundStyle(Theme.textSecondary)
                        StatusBadge(title: "Verified", symbol: "checkmark.seal.fill", tone: .positive)
                    }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
    }
}

// MARK: - Create Branch Sheet

struct ReflogCreateBranchSheet: View {
    @Environment(ReflogViewModel.self) private var viewModel
    let entry: ReflogEntry
    let index: Int

    @State private var name = ""
    @State private var checkout = false

    private var isValid: Bool {
        RefName.isValid(name.trimmingCharacters(in: .whitespaces))
    }

    var body: some View {
        Form {
            Section {
                TextField("Branch name", text: $name, prompt: Text("feature/recovered-work"))
                    .onSubmit(create)
                Toggle("Check out after creating", isOn: $checkout)
            } header: {
                Text("New branch at HEAD@{\(index)} \u{00B7} \(entry.newSHA.prefix(7))")
            } footer: {
                if !name.isEmpty && !isValid {
                    Text("Branch names can't contain spaces, \u{201C}..\u{201D}, or ~ ^ : ? * [ \\")
                        .font(.caption)
                        .foregroundStyle(Theme.danger)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { viewModel.cancelCreateBranch() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create Branch", action: create).disabled(!isValid)
            }
        }
    }

    private func create() {
        guard isValid else { return }
        Task { await viewModel.createBranch(named: name, checkout: checkout) }
    }
}

#Preview {
    let vm = ReflogViewModel(repository: MockGitRepository())
    return ReflogDetailPanel()
        .environment(vm)
        .frame(width: 560, height: 480)
        .padding()
        .background(Theme.background)
        .task {
            await vm.refresh()
            if let first = vm.entries.first { await vm.select(first) }
        }
}
