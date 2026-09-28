// Views/WorkingCopy/PatchSheets.swift
// Grove
//
// Apply Patch sheet with its inline `git apply --check` result, and the save panel for Create Patch.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Presents the patch open panel and the Apply Patch sheet for the working copy.
struct PatchDialogs: ViewModifier {
    let viewModel: WorkingCopyViewModel

    private static let patchTypes: [UTType] = [
        UTType(filenameExtension: "patch"), UTType(filenameExtension: "diff"), .plainText
    ].compactMap { $0 }

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: Binding(get: { viewModel.isChoosingPatch }, set: { viewModel.setChoosingPatch($0) }),
                          allowedContentTypes: Self.patchTypes) { result in
                if case .success(let url) = result { Task { await viewModel.beginApplyPatch(url) } }
            }
            .sheet(item: Binding(get: { viewModel.patchApply }, set: { if $0 == nil { viewModel.cancelApplyPatch() } })) { request in
                ApplyPatchSheet(request: request, viewModel: viewModel)
            }
    }
}

/// Asks where to save, then writes the entries' staged or unstaged changes as a patch.
@MainActor
func savePatch(_ entries: [StatusEntry], side: DiffSide, viewModel: WorkingCopyViewModel) async {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = viewModel.suggestedPatchName(for: entries)
    panel.allowedContentTypes = [UTType(filenameExtension: "patch") ?? .plainText]
    let files = entries.count == 1 ? entries[0].fileName : "\(entries.count) files"
    panel.message = "Save the \(side == .staged ? "staged" : "unstaged") changes of \(files) as a patch"
    panel.prompt = "Create Patch"
    guard await panel.begin() == .OK, let url = panel.url else { return }
    await viewModel.createPatch(from: entries, side: side, to: url)
}

private struct ApplyPatchSheet: View {
    let request: PatchApplyRequest
    let viewModel: WorkingCopyViewModel

    var body: some View {
        DialogSheet(
            title: "Apply Patch",
            message: "Changes the working copy with the patch. Grove checks that it applies before changing anything.",
            symbol: "doc.badge.plus",
            progress: request.isApplying ? "Applying\u{2026}" : nil,
            primaryTitle: "Apply",
            isPrimaryDisabled: !request.canApply,
            onCancel: { viewModel.cancelApplyPatch() },
            onPrimary: { Task { await viewModel.applyPendingPatch() } }
        ) {
            DialogCard {
                DialogField("Patch") {
                    Text(abbreviatingHome(request.file.path))
                        .font(.monoCaption)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(request.file.path)
                }
                DialogField("Index") {
                    Toggle("Also stage the changes",
                           isOn: Binding(get: { request.toIndex }, set: { on in Task { await viewModel.setPatchAppliesToIndex(on) } }))
                        .toggleStyle(.checkbox)
                }
            }
            checkResult
        }
    }

    @ViewBuilder
    private var checkResult: some View {
        switch request.check {
        case .checking:
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView().controlSize(.small)
                Text("Checking the patch\u{2026}").foregroundStyle(Theme.textSecondary)
            }
            .font(.system(size: 13))
        case .applies:
            Label("The patch applies cleanly.", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Theme.success)
        case .fails(let message):
            Banner(symbol: "xmark.octagon", message: message, tone: .negative)
        }
    }
}

#Preview("Apply Patch") {
    let vm = WorkingCopyViewModel(repository: MockGitRepository())
    ApplyPatchSheet(request: PatchApplyRequest(file: URL(fileURLWithPath: "/tmp/fix-login.patch"),
                                               check: .fails("error: patch failed: src/app.swift:3")),
                    viewModel: vm)
}
