// Views/Sidebar/SidebarViewModel+Export.swift
// Grove

import Foundation
import GroveKit

extension SidebarViewModel {

    func archiveFileName(for ref: String) -> String {
        "\(repository.displayName)-\(SavePanel.slug(ref)).zip"
    }

    /// Writes `ref`'s files as an archive at `url`.
    func exportFiles(of ref: String, to url: URL) async {
        do {
            try await repository.archive(revision: ref, to: url)
        } catch {
            errorMessage = "Couldn't export the files: \(error.localizedDescription)"
        }
    }
}
