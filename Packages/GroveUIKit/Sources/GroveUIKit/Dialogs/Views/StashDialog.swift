// Dialogs/Views/StashDialog.swift
// GroveUIKit

#if os(macOS)
import GroveKit
import SwiftUI

/// Saves local changes to a new stash, either everything or selected files.
struct StashDialog: View {
    @Environment(\.gitStyle) private var style
    let context: GitDialogContext
    let close: (Bool) -> Void
    @State private var form: GitStashForm
    @State private var entries: [StatusEntry] = []
    @State private var isLoading = true
    @State private var operation = DialogOperation()

    init(paths: [String]?, context: GitDialogContext, close: @escaping (Bool) -> Void) {
        self.context = context
        self.close = close
        _form = State(initialValue: GitStashForm(paths: paths))
    }

    var body: some View {
        GitDialogSheet(
            title: "Stash Changes",
            message: "Puts your uncommitted changes aside and resets the working copy to HEAD. Apply the stash later to get them back.",
            symbol: "tray.and.arrow.down",
            progress: operation.title, errorMessage: operation.errorMessage,
            primaryTitle: form.selectFiles ? "Stash \(form.paths.count) Files" : "Stash All",
            isPrimaryDisabled: entries.isEmpty || form.commands.isEmpty, blocker: form.unsupportedReason(context.features),
            onCancel: { close(false) }, onPrimary: stash
        ) {
            GitDialogCard {
                GitDialogField("Message") {
                    TextField("Optional description", text: $form.message)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(stash)
                        .gitInitialFocus()
                }
                GitDialogOptionRow(isOn: $form.includeUntracked, label: "Include Untracked Files")
                GitDialogOptionRow(isOn: $form.keepIndex, label: "Keep Staged Changes",
                                   description: "What's staged is stashed and also stays in the working copy.")
                GitDialogOptionRow(isOn: $form.selectFiles, label: "Stash Selected Files Only",
                                   description: "Choose which changed files to put aside.")
            }
            if form.selectFiles {
                fileList
            } else if !isLoading && entries.isEmpty {
                GitBanner(symbol: "checkmark.circle", message: "There are no local changes to stash.")
            }
        }
        .task { await load() }
    }

    private var allSelected: Bool { !entries.isEmpty && form.paths.count == entries.count }

    private var fileList: some View {
        VStack(spacing: 0) {
            GitPanelHeader(title: "Files", detail: "\(form.paths.count) of \(entries.count)") {
                Button(allSelected ? "Deselect All" : "Select All") {
                    form.paths = allSelected ? [] : Set(entries.map(\.path))
                }
                .buttonStyle(.borderless)
                .font(style.font(12))
                .gitClickable()
            }
            if isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(entries) { row($0) }
                    }
                    .padding(.vertical, GitMetrics.Spacing.xs)
                }
                .frame(minHeight: 80, maxHeight: 200 * style.fontScale)
            }
        }
        .gitPanel()
    }

    private func row(_ entry: StatusEntry) -> some View {
        let isSelected = form.paths.contains(entry.path)
        let directory = (entry.path as NSString).deletingLastPathComponent
        return Button {
            if isSelected { form.paths.remove(entry.path) } else { form.paths.insert(entry.path) }
        } label: {
            HStack(spacing: GitMetrics.Spacing.sm) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? style.accent : style.textSecondary)
                Text((entry.path as NSString).lastPathComponent).font(style.font(13)).lineLimit(1)
                if !directory.isEmpty {
                    Text(directory).font(style.monoCaption).foregroundStyle(style.textSecondary).lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, GitMetrics.Spacing.md)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gitClickable()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func load() async {
        defer { isLoading = false }
        do {
            entries = try await context.repository.status().filter { $0.indexStatus != .unmodified || $0.workdirStatus != .unmodified }
            let all = Set(entries.map(\.path))
            form.paths = form.selectFiles ? form.paths.intersection(all) : all
        } catch {
            operation.errorMessage = error.localizedDescription
        }
    }

    private func stash() {
        guard !entries.isEmpty, !form.commands.isEmpty, form.unsupportedReason(context.features) == nil else { return }
        operation.submit("Stashing", form, context: context, close: close)
    }
}
#endif
