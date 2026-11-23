// WorkingCopy/PatchSheets.swift
// GroveUIKit
//
// Apply Patch with its inline `git apply --check` result, and where Create Patch saves.

#if os(macOS)
import AppKit
import GroveKit
import SwiftUI
import UniformTypeIdentifiers

/// Asks for a patch when the view model wants one, then shows Apply Patch.
struct PatchDialogs: ViewModifier {
    let viewModel: WorkingCopyViewModel
    let host: GitWorkingCopyHost

    func body(content: Content) -> some View {
        content
            .onChange(of: viewModel.isChoosingPatch, initial: true) { _, choosing in
                guard choosing else { return }
                Task {
                    let file = await (host.choosePatch ?? Self.openPanel)()
                    if let file { await viewModel.beginApplyPatch(file) } else { viewModel.setChoosingPatch(false) }
                }
            }
            .sheet(item: Binding(get: { viewModel.patchApply }, set: { if $0 == nil { viewModel.cancelApplyPatch() } })) { request in
                ApplyPatchSheet(request: request, viewModel: viewModel)
            }
    }

    @MainActor
    static func openPanel() async -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "patch"), UTType(filenameExtension: "diff"), .plainText]
            .compactMap { $0 }
        panel.message = "Choose a patch to apply to the working tree"
        return await panel.begin() == .OK ? panel.url : nil
    }
}

/// Asks where to save, then writes the entries' staged or unstaged changes as a patch.
@MainActor
func createPatch(_ entries: [StatusEntry], side: DiffSide, viewModel: WorkingCopyViewModel, host: GitWorkingCopyHost) async {
    let name = viewModel.suggestedPatchName(for: entries)
    let files = entries.count == 1 ? entries[0].fileName : "\(entries.count) files"
    let message = "Save the \(side == .staged ? "staged" : "unstaged") changes of \(files) as a patch"
    guard let url = await (host.choosePatchDestination ?? savePanel)(name, message) else { return }
    viewModel.clearError()
    await viewModel.createPatch(from: entries, side: side, to: url)
    host.onEvent?(.patchCreated(succeeded: viewModel.errorMessage == nil))
}

@MainActor
private func savePanel(_ name: String, _ message: String) async -> URL? {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    panel.allowedContentTypes = [UTType(filenameExtension: "patch") ?? .plainText]
    panel.message = message
    panel.prompt = "Create Patch"
    return await panel.begin() == .OK ? panel.url : nil
}

private struct ApplyPatchSheet: View {
    @Environment(\.gitStyle) private var style
    let request: PatchApplyRequest
    let viewModel: WorkingCopyViewModel

    private var current: PatchApplyRequest { viewModel.patchApply ?? request }

    var body: some View {
        GitDialogSheet(
            title: "Apply Patch",
            message: "Changes the working copy with the patch, after checking that it applies.",
            symbol: "doc.badge.plus",
            progress: current.isApplying ? "Applying" : nil,
            primaryTitle: "Apply",
            isPrimaryDisabled: !current.canApply,
            onCancel: { viewModel.cancelApplyPatch() },
            onPrimary: { Task { await viewModel.applyPendingPatch() } }
        ) {
            GitDialogCard {
                GitDialogField("Patch") {
                    Text(current.file.lastPathComponent)
                        .font(style.monoCaption)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(current.file.path)
                }
                GitDialogField("Index") {
                    Toggle("Also stage the changes",
                           isOn: Binding(get: { current.toIndex }, set: { on in Task { await viewModel.setPatchAppliesToIndex(on) } }))
                        .toggleStyle(.checkbox)
                        .disabled(current.isApplying)
                        .gitClickable()
                }
            }
            checkResult
        }
    }

    @ViewBuilder
    private var checkResult: some View {
        switch current.check {
        case .checking:
            HStack(spacing: GitMetrics.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Checking the patch").foregroundStyle(style.textSecondary)
            }
            .font(style.font(13))
        case .applies:
            Label("The patch applies cleanly.", systemImage: "checkmark.circle.fill")
                .font(style.font(13))
                .foregroundStyle(style.success)
        case .fails(let message):
            ScrollView {
                GitBanner(symbol: "xmark.octagon", message: message, tone: .negative)
            }
            .frame(maxHeight: 160)
        }
    }
}

#Preview("Apply Patch") {
    ApplyPatchSheet(request: PatchApplyRequest(file: URL(fileURLWithPath: "/tmp/fix-login.patch"),
                                               check: .fails("error: patch failed: src/app.swift:3")),
                    viewModel: WorkingCopyViewModel(repository: MockGitRepository()))
}
#endif
