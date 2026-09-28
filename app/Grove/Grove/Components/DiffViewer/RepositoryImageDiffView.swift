// Components/DiffViewer/RepositoryImageDiffView.swift
// Grove
//
// Loads both versions of an image file from the repository and shows them in ImageDiffView.

import AppKit
import SwiftUI

/// Where a changeset's image files are read from; one pair of revisions covers every file.
struct ImageDiffSource {
    let repository: any GitRepositoryProtocol
    let old: FileRevision
    let new: FileRevision

    /// A commit against its first parent.
    static func commit(_ sha: String, in repository: any GitRepositoryProtocol) -> ImageDiffSource {
        ImageDiffSource(repository: repository, old: .commit("\(sha)^"), new: .commit(sha))
    }
}

struct RepositoryImageDiffView: View {
    let repository: any GitRepositoryProtocol
    let path: String
    /// Path on the old side when the file was renamed.
    var oldPath: String?
    let old: FileRevision
    let new: FileRevision
    /// Change it to reload, e.g. when the working tree was refreshed.
    var reloadToken: AnyHashable = 0

    @State private var images: LoadedImages?

    init(repository: any GitRepositoryProtocol, path: String, oldPath: String? = nil,
         old: FileRevision, new: FileRevision, reloadToken: AnyHashable = 0) {
        self.repository = repository
        self.path = path
        self.oldPath = oldPath
        self.old = old
        self.new = new
        self.reloadToken = reloadToken
    }

    init(source: ImageDiffSource, path: String, oldPath: String? = nil) {
        self.init(repository: source.repository, path: path, oldPath: oldPath, old: source.old, new: source.new)
    }

    private struct LoadedImages {
        let old: NSImage?
        let new: NSImage?
    }

    var body: some View {
        Group {
            if let images {
                ImageDiffView(oldImage: images.old.map(Image.init(nsImage:)),
                              newImage: images.new.map(Image.init(nsImage:)),
                              oldSize: images.old?.size,
                              newSize: images.new?.size)
            } else {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: [AnyHashable(path), AnyHashable(old), AnyHashable(new), reloadToken]) {
            // A side that fails to load (added/deleted file, root commit) renders as missing.
            let oldBytes = try? await repository.fileData(path: oldPath ?? path, at: old)
            let newBytes = try? await repository.fileData(path: path, at: new)
            images = LoadedImages(old: oldBytes.flatMap(NSImage.init(data:)),
                                  new: newBytes.flatMap(NSImage.init(data:)))
        }
    }
}

#Preview {
    RepositoryImageDiffView(repository: MockGitRepository(), path: "logo.png", old: .index, new: .workingTree)
        .frame(width: 600, height: 400)
        .panel()
        .padding()
        .background(Theme.background)
}
