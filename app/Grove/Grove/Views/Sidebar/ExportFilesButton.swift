// Views/Sidebar/ExportFilesButton.swift
// Grove

import SwiftUI
import UniformTypeIdentifiers

/// Context-menu item that saves a branch or tag's files as a ZIP archive.
struct ExportFilesButton: View {
    @Environment(SidebarViewModel.self) private var viewModel
    let ref: String

    var body: some View {
        Button("Export Files\u{2026}", systemImage: "square.and.arrow.up") {
            Task {
                guard let url = await SavePanel.choose(name: viewModel.archiveFileName(for: ref),
                                                       message: "Export the files of \u{201C}\(ref)\u{201D} as a ZIP archive",
                                                       prompt: "Export", type: .zip) else { return }
                await viewModel.exportFiles(of: ref, to: url)
            }
        }
    }
}
