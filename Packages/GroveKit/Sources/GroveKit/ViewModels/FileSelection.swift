// ViewModels/FileSelection.swift
// GroveKit

import Foundation

/// A file row in the Changes list: a partially staged file has one row per side.
public struct FileRow: Hashable {
    public let path: String
    public let side: DiffSide

    public init(path: String, side: DiffSide) {
        self.path = path
        self.side = side
    }
}

public typealias FileSelection = ListSelection<FileRow>
