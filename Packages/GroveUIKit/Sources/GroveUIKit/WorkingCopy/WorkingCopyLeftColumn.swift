// WorkingCopy/WorkingCopyLeftColumn.swift
// GroveUIKit
//
// The composer, or the operation's banner while one is in progress, over the file list.

#if os(macOS)
import GroveKit
import SwiftUI

struct WorkingCopyLeftColumn: View {
    var body: some View {
        VStack(spacing: GitMetrics.Spacing.md) {
            WorkingCopyComposerArea(showsComposer: true)
            WorkingCopyFiles()
        }
    }
}

/// The file list, or the app's replacement for it.
struct WorkingCopyFiles: View {
    @Environment(\.workingCopySlots) private var slots

    var body: some View {
        if let replacement = slots.replacement {
            replacement.files.gitPanel()
        } else {
            FileStatusList()
        }
    }
}

/// The LFS warning, then the composer or the operation's banner; without the composer only the warning.
struct WorkingCopyComposerArea: View {
    @Environment(WorkingCopyViewModel.self) private var viewModel
    let showsComposer: Bool

    var body: some View {
        if viewModel.showsLFSWarning {
            GitBanner(symbol: "externaldrive.badge.exclamationmark", message: LFSStatus.missingMessage,
                      onDismiss: viewModel.dismissLFSWarning)
        }
        if showsComposer {
            if viewModel.isInOperation {
                GitOperationBanner()
            } else {
                GitCommitComposer()
            }
        }
    }
}
#endif
