// Views/Dialogs/StashDialogView.swift
// Grove

import GroveKit
import SwiftUI

/// Saves local changes to a new stash, either everything or selected files.
struct StashDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol
    var onComplete: () -> Void = {}

    @State private var message = ""
    @State private var includeUntracked = true
    @State private var selectFiles = false
    @State private var statusEntries: [StatusEntry] = []
    @State private var selectedPaths: Set<String> = []
    @State private var isLoadingStatus = true
    @State private var isStashing = false
    @State private var errorMessage: String?

    var body: some View {
        DialogSheet(
            title: "Stash Changes",
            message: "Puts your uncommitted changes aside and resets the working copy to HEAD. Apply the stash later to get them back.",
            symbol: "tray.and.arrow.down",
            progress: isStashing ? "Stashing…" : nil,
            errorMessage: errorMessage,
            primaryTitle: selectFiles ? "Stash \(selectedPaths.count) Files" : "Stash All",
            isPrimaryDisabled: statusEntries.isEmpty || (selectFiles && selectedPaths.isEmpty),
            onCancel: { dismiss() },
            onPrimary: performStash
        ) {
            DialogCard {
                DialogField("Message") {
                    TextField("Optional description", text: $message)
                        .textFieldStyle(.roundedBorder)
                }
                DialogOptionRow(isOn: $includeUntracked, label: "Include Untracked Files")
                DialogOptionRow(
                    isOn: $selectFiles,
                    label: "Stash Selected Files Only",
                    description: "Choose which changed files to put aside."
                )
            }
            if selectFiles {
                fileList
            } else if !isLoadingStatus && statusEntries.isEmpty {
                Banner(symbol: "checkmark.circle", message: "There are no local changes to stash.")
            }
        }
        .task { await loadStatus() }
    }

    // MARK: File List

    private var fileList: some View {
        VStack(spacing: 0) {
            PanelHeader(title: "Files", detail: "\(selectedPaths.count) of \(statusEntries.count)") {
                Button(allSelected ? "Deselect All" : "Select All") {
                    selectedPaths = allSelected ? [] : Set(statusEntries.map(\.path))
                }
                .buttonStyle(.borderless)
                .font(.system(size: 12))
            }
            if isLoadingStatus {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(statusEntries) { fileRow($0) }
                    }
                    .padding(.vertical, Theme.Spacing.xs)
                }
                .frame(minHeight: 80, maxHeight: 200)
            }
        }
        .panel()
    }

    private var allSelected: Bool {
        !statusEntries.isEmpty && selectedPaths.count == statusEntries.count
    }

    private func fileRow(_ entry: StatusEntry) -> some View {
        let isSelected = selectedPaths.contains(entry.path)
        let directory = (entry.path as NSString).deletingLastPathComponent
        return HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
            Text((entry.path as NSString).lastPathComponent)
                .font(.system(size: 13))
                .lineLimit(1)
            if !directory.isEmpty {
                Text(directory)
                    .font(.monoCaption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected { selectedPaths.remove(entry.path) } else { selectedPaths.insert(entry.path) }
        }
    }

    // MARK: Actions

    private func loadStatus() async {
        defer { isLoadingStatus = false }
        do {
            statusEntries = try await repository.status().filter {
                $0.indexStatus != .unmodified || $0.workdirStatus != .unmodified
            }
            selectedPaths = Set(statusEntries.map(\.path))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performStash() {
        isStashing = true
        errorMessage = nil
        Task {
            do {
                let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
                try await repository.stashCreate(
                    message: text.isEmpty ? nil : text,
                    includeUntracked: includeUntracked,
                    paths: selectFiles ? Array(selectedPaths) : nil
                )
                onComplete()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isStashing = false
            }
        }
    }
}

#Preview {
    StashDialogView(repository: MockGitRepository())
}
