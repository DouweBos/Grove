// FixtureStates.swift
// GroveTests
//
// Applies the composable state flags (conflicts, dirt, stashes, divergence) to a generated repository.

import Foundation

extension FixtureGenerator {

    // swiftlint:disable:next cyclomatic_complexity
    func applyStates() throws {
        var rng = FixtureRandom(seed: spec.seed &+ 7)
        let tracked = FixtureGit.lines(try FixtureGit.run(["ls-files", "src"], in: repo))
        var files = tracked
        // Each state edits its own files so later states (dirt) never clobber a conflict; reuse only when out of files.
        func takeFile() -> String {
            if files.isEmpty {
                files = tracked.filter { FileManager.default.fileExists(atPath: repo.appendingPathComponent($0).path) }
            }
            return files.remove(at: rng.int(files.count))
        }
        for state in spec.sortedStates {
            switch state {
            case .missingWorktree: try addMissingWorktree()
            case .diverged: try diverge()
            case .noUpstream: try FixtureGit.run(["checkout", "-q", "-b", "wip/no-upstream"], in: repo)
            case .largeFile: try addLargeFile()
            case .binaryImage: try addImage()
            case .stashes(let count): try addStashes(count, takeFile: takeFile)
            case .detached: try FixtureGit.run(["checkout", "-q", "--detach", "HEAD~2"], in: repo)
            case .mergeConflict: try conflict(file: takeFile(), extra: takeFile(), rebase: false)
            case .rebaseConflict: try conflict(file: takeFile(), extra: takeFile(), rebase: true)
            case .dirty(let count): try makeDirty(count, takeFile: takeFile)
            }
        }
    }

    // MARK: - History states

    /// Origin gets three commits the clone lacks; the clone gets two origin lacks.
    private func diverge() throws {
        try FixtureGit.run(["checkout", "-q", "--detach"], in: repo)
        for index in 1...3 {
            try FixtureGit.commit(["notes/upstream-\(index).md": Data("Upstream note \(index)\n".utf8)],
                                  message: "docs: upstream note \(index)", in: repo, date: tick())
        }
        try FixtureGit.run(["push", "-q", "origin", "HEAD:refs/heads/main"], in: repo)
        try FixtureGit.run(["checkout", "-q", "main"], in: repo)
        try FixtureGit.run(["fetch", "-q", "--no-tags", "origin", "main"], in: repo)
        for index in 1...2 {
            try FixtureGit.commit(["notes/local-\(index).md": Data("Local note \(index)\n".utf8)],
                                  message: "docs: local note \(index)", in: repo, date: tick())
        }
    }

    /// A ~3 MB text file committed, then rewritten in chunks so both its commit and working diff are huge.
    private func addLargeFile() throws {
        var rng = FixtureRandom(seed: spec.seed &+ 11)
        let lines = (0..<60_000).map { "  {\"id\": \($0), \"title\": \"\(FixtureVocabulary.codeLine(&rng, $0).count)\"}," }
        try FixtureGit.commit(["data/catalog.json": Data(("[\n" + lines.joined(separator: "\n") + "\n]\n").utf8)],
                              message: "chore(data): snapshot catalog", in: repo, date: tick())
        let edited = lines.enumerated().map { $0.offset % 25 == 0 ? $0.element.replacingOccurrences(of: "title", with: "name") : $0.element }
        try Data(("[\n" + edited.joined(separator: "\n") + "\n]\n").utf8)
            .write(to: repo.appendingPathComponent("data/catalog.json"))
    }

    private func addImage() throws {
        let path = "assets/artwork.png"
        try FixtureGit.commit([path: FixturePNG.make(width: 256, height: 256, seed: 1)],
                              message: "feat(ui): add artwork", in: repo, date: tick())
        try FixturePNG.make(width: 256, height: 256, seed: 2).write(to: repo.appendingPathComponent(path))
    }

    private func addStashes(_ count: Int, takeFile: () -> String) throws {
        for index in 0..<count {
            for _ in 0...(index % 3) { try edit(takeFile(), marker: "stash \(index)") }
            try FixtureGit.run(["stash", "push", "-q", "-m", "WIP \(index): try another approach"], in: repo, date: tick())
        }
    }

    // MARK: - Conflicts

    /// Both sides rewrite the first line of `file`; `extra` changes cleanly so the merge also has staged changes.
    private func conflict(file: String, extra: String, rebase: Bool) throws {
        let head = try FixtureGit.run(["rev-parse", "HEAD"], in: repo).trimmingCharacters(in: .whitespacesAndNewlines)
        let branch = try FixtureGit.run(["symbolic-ref", "-q", "--short", "HEAD"], in: repo, allowFailure: true)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let other = rebase ? "conflict/upstream" : "conflict/incoming"
        try FixtureGit.run(["checkout", "-q", "-b", other], in: repo)
        try replaceFirstLine(of: file, with: "// \(other) wins")
        try edit(extra, marker: other)
        try FixtureGit.run(["commit", "-q", "-am", "fix: resolve on \(other)"], in: repo, date: tick())
        try FixtureGit.run(["checkout", "-q", branch.isEmpty ? head : branch], in: repo)
        try replaceFirstLine(of: file, with: "// local change wins")
        try FixtureGit.run(["commit", "-q", "-am", "fix: local take on \(file)"], in: repo, date: tick())
        let command = rebase ? ["rebase", other] : ["merge", "--no-edit", other]
        try FixtureGit.run(command, in: repo, date: tick(), allowFailure: true)
    }

    // MARK: - Working copy

    /// Roughly 40% modified, 30% staged (some also modified after staging), 20% untracked, 10% deleted.
    private func makeDirty(_ count: Int, takeFile: () -> String) throws {
        var stage: [String] = [], remove: [String] = []
        for index in 0..<count {
            switch index % 10 {
            case 0...3:
                try edit(takeFile(), marker: "dirty \(index)")
            case 4...6:
                let file = takeFile()
                try edit(file, marker: "staged \(index)")
                stage.append(file)
            case 7, 8:
                let url = repo.appendingPathComponent("src/scratch/Untracked\(index).ts")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data("export const draft\(index) = \(index);\n".utf8).write(to: url)
            default:
                let file = takeFile()
                try FileManager.default.removeItem(at: repo.appendingPathComponent(file))
                remove.append(file)
            }
        }
        if !stage.isEmpty { try FixtureGit.run(["add", "--"] + stage, in: repo) }
        if !remove.isEmpty { try FixtureGit.run(["rm", "-q", "--cached", "--"] + remove, in: repo) }
        for (index, file) in stage.enumerated() where index % 3 == 2 {
            try edit(file, marker: "unstaged after staging")
        }
    }

    private func edit(_ path: String, marker: String) throws {
        let url = repo.appendingPathComponent(path)
        var lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        let position = min(lines.count - 1, max(0, lines.count / 2))
        lines.insert("  // \(marker)", at: position)
        lines[0] += " // edited"
        try Data(lines.joined(separator: "\n").utf8).write(to: url)
    }

    private func replaceFirstLine(of path: String, with text: String) throws {
        let url = repo.appendingPathComponent(path)
        var lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
        lines[0] = text
        try Data(lines.joined(separator: "\n").utf8).write(to: url)
    }
}

/// Minimal PNG encoder (stored deflate blocks), so fixtures need no image tools and bytes never vary.
enum FixturePNG {
    static func make(width: Int, height: Int, seed: Int) -> Data {
        var raw = [UInt8]()
        raw.reserveCapacity((width * 3 + 1) * height)
        for row in 0..<height {
            raw.append(0)
            for column in 0..<width {
                let band = (row / 32 + column / 32 + seed) % 2 == 0
                raw += band ? [UInt8(column % 256), UInt8(row % 256), UInt8(seed * 90 % 256)] : [30, 30, UInt8(40 * seed % 256)]
            }
        }
        var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        png += chunk("IHDR", be32(width) + be32(height) + [8, 2, 0, 0, 0])
        png += chunk("IDAT", zlibStored(raw))
        png += chunk("IEND", [])
        return Data(png)
    }

    private static func zlibStored(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var offset = 0
        repeat {
            let size = min(65_535, data.count - offset)
            let last: UInt8 = offset + size >= data.count ? 1 : 0
            out += [last, UInt8(size & 0xFF), UInt8(size >> 8), UInt8(~size & 0xFF), UInt8((~size >> 8) & 0xFF)]
            out += data[offset..<offset + size]
            offset += size
        } while offset < data.count
        var sumA: UInt32 = 1, sumB: UInt32 = 0
        for byte in data {
            sumA = (sumA + UInt32(byte)) % 65_521
            sumB = (sumB + sumA) % 65_521
        }
        return out + be32(Int(sumB << 16 | sumA))
    }

    private static func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        let typed = Array(type.utf8) + body
        return be32(body.count) + typed + be32(Int(crc32(typed)))
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }

    private static func be32(_ value: Int) -> [UInt8] {
        [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
