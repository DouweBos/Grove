// Conflicts/ConflictResult.swift
// GroveUIKit
//
// A conflicted file as it sits in the working tree, read where the worktree is.

#if os(macOS)
import Foundation
import GroveKit

enum ConflictResult: Equatable {
    case loading
    case loaded(String)
    /// Unknown contents: never offered for saving, which would replace the file with them.
    case unreadable(String)

    var text: String? {
        if case .loaded(let text) = self { text } else { nil }
    }

    /// Through the repository's runner, so a worktree on another machine reads there.
    static func read(_ path: String, from repository: any GitRepositoryProtocol) async -> ConflictResult {
        await decode { try await repository.fileData(path: path, at: .workingTree) }
    }

    static func read(_ path: String, in worktree: URL, runner: any GitRunner) async -> ConflictResult {
        await decode { try await runner.readFile(at: worktree.appendingPathComponent(path)) }
    }

    private static func decode(_ read: () async throws -> Data) async -> ConflictResult {
        do {
            let data = try await read()
            // Unlike `String(data:encoding:)`, keeps a byte order mark for the save to write back.
            guard let text = String(validating: data, as: UTF8.self), !text.looksBinary else {
                return .unreadable("It isn't text. Take a side, or resolve it in another app.")
            }
            return .loaded(text)
        } catch {
            return .unreadable(error.localizedDescription)
        }
    }
}

extension String {
    /// Has conflict markers left in it; byte search, as this runs on every edit of a 100k-line file.
    var hasConflictMarkers: Bool {
        containsBytes("<<<<<<< ") || containsBytes(">>>>>>> ")
    }

    /// Bytes no text editor should show, e.g. an image's.
    var looksBinary: Bool { containsBytes("\u{0}") }

    private func containsBytes(_ needle: String) -> Bool {
        var haystack = self
        var needle = needle
        return haystack.withUTF8 { text in
            needle.withUTF8 { pattern in
                memmem(text.baseAddress, text.count, pattern.baseAddress, pattern.count) != nil
            }
        }
    }
}
#endif
