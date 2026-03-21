// Views/Dialogs/StashDialogView.swift
// Grove
//
// Stash creation dialog: message field, include-untracked toggle,
// and a file list for partial stash (stash selected files only).

import SwiftUI

// MARK: - StashDialogView

/// Dialog for creating a new stash.
///
/// Supports full stash (all changes) or partial stash (selected files only).
/// When the "Stash Selected" mode is active, a file list appears so the user
/// can check individual files to include.
struct StashDialogView: View {

    @Environment(\.dismiss) private var dismiss

    let repository: any GitRepositoryProtocol

    // MARK: State

    @State private var message = ""
    @State private var includeUntracked = true
    @State private var isStashingAll = true
    @State private var statusEntries: [StatusEntry] = []
    @State private var selectedPaths: Set<String> = []
    @State private var isLoadingStatus = false
    @State private var isStashing = false
    @State private var errorMessage: String?

    // MARK: Computed

    private var primaryLabel: String {
        if isStashing { return "Stashing\u{2026}" }
        return isStashingAll ? "Stash All" : "Stash Selected"
    }

    private var isPrimaryDisabled: Bool {
        if isStashing { return true }
        if !isStashingAll && selectedPaths.isEmpty { return true }
        return false
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Stash Changes",
                description: "Saves your local modifications to a new stash entry and reverts the working directory to match HEAD."
            )

            Divider()

            Form {
                LabeledContent("Message") {
                    TextField("Optional stash message", text: $message)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle("Include Untracked Files", isOn: $includeUntracked)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Stash Selected Files Only", isOn: stashSelectedBinding)
                        .fontWeight(.medium)
                    Text("Choose individual files to include instead of stashing all changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
                .padding(.vertical, 4)
            }
            .formStyle(.grouped)

            // File selection list shown in "Stash Selected" mode.
            if !isStashingAll {
                fileSelectionList
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 4)
            }

            Divider()

            SheetFooter(
                cancelAction: { dismiss() },
                primaryLabel: primaryLabel,
                primaryAction: performStash,
                isPrimaryDisabled: isPrimaryDisabled
            )
        }
        .frame(width: 440)
        .task { await loadStatus() }
    }

    // MARK: Binding

    /// Inverts `isStashingAll` and loads status entries on first activation.
    private var stashSelectedBinding: Binding<Bool> {
        Binding(
            get: { !isStashingAll },
            set: { newValue in
                isStashingAll = !newValue
                if newValue && statusEntries.isEmpty {
                    Task { await loadStatus() }
                }
            }
        )
    }

    // MARK: File Selection List

    private var fileSelectionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Files to Stash")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 4)

                Spacer()

                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected {
                        selectedPaths.removeAll()
                    } else {
                        selectedPaths = Set(statusEntries.map(\.path))
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
                .padding(.trailing, 16)
                .padding(.top, 4)
            }

            Divider()

            if isLoadingStatus {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if statusEntries.isEmpty {
                Text("No changed files.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(statusEntries) { entry in
                            fileRow(entry)
                        }
                    }
                }
                .frame(minHeight: 80, maxHeight: 200)
            }
        }
        .background(Color(white: 0.15, opacity: 0.5))
    }

    private var allSelected: Bool {
        !statusEntries.isEmpty && selectedPaths.count == statusEntries.count
    }

    private func fileRow(_ entry: StatusEntry) -> some View {
        let isSelected = selectedPaths.contains(entry.path)
        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(URL(fileURLWithPath: entry.path).lastPathComponent)
                    .font(.system(size: 12))
                    .lineLimit(1)

                let dir = URL(fileURLWithPath: entry.path)
                    .deletingLastPathComponent().path
                if dir != "." {
                    Text(dir)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedPaths.remove(entry.path)
            } else {
                selectedPaths.insert(entry.path)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    // MARK: Actions

    private func loadStatus() async {
        isLoadingStatus = true
        defer { isLoadingStatus = false }
        do {
            let entries = try await repository.status()
            // Only list files that actually have changes.
            statusEntries = entries.filter {
                $0.indexStatus != .unmodified || $0.workdirStatus != .unmodified
            }
            // Pre-select all files so "Stash Selected" works out of the box.
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
                let msg = message.trimmingCharacters(in: .whitespacesAndNewlines)
                let paths: [String]? = isStashingAll ? nil : Array(selectedPaths)
                try await repository.stashCreate(
                    message: msg.isEmpty ? nil : msg,
                    includeUntracked: includeUntracked,
                    paths: paths
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isStashing = false
            }
        }
    }
}

// MARK: - Preview

#Preview {
    StashDialogView(repository: MockGitRepository())
}
