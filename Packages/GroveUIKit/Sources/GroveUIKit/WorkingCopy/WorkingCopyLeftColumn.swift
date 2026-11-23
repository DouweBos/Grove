// WorkingCopy/WorkingCopyLeftColumn.swift
// GroveUIKit
//
// The composer, or the operation's banner while one is in progress, over the file list.

#if os(macOS)
import GroveKit
import SwiftUI

struct WorkingCopyLeftColumn: View {
    @Environment(\.gitStyle) private var style
    @Environment(WorkingCopyViewModel.self) private var viewModel
    @Environment(\.workingCopySlots) private var slots
    /// Horizontal when the detail goes below in narrow windows.
    var axis: Axis = .vertical

    var body: some View {
        if axis == .vertical {
            VStack(spacing: GitMetrics.Spacing.md) {
                composer
                files
            }
        } else {
            HStack(alignment: .top, spacing: GitMetrics.Spacing.md) {
                composer.frame(maxWidth: .infinity)
                files.frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var files: some View {
        if let replacement = slots.replacement {
            replacement.files.gitPanel()
        } else {
            FileStatusList()
        }
    }

    @ViewBuilder
    private var composer: some View {
        if viewModel.showsLFSWarning {
            GitBanner(symbol: "externaldrive.badge.exclamationmark", message: LFSStatus.missingMessage,
                      onDismiss: viewModel.dismissLFSWarning)
        }
        if viewModel.isInOperation {
            GitOperationBanner()
        } else {
            GitCommitComposer()
        }
    }
}
#endif
