// Views/WorkingCopy/FileSelection.swift
// Grove

import Foundation

/// A file row in the Changes list: a partially staged file has one row per side.
struct FileRow: Hashable {
    let path: String
    let side: DiffSide
}

typealias FileSelection = ListSelection<FileRow>
