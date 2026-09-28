// GitKit/Parsers/SubmoduleParser.swift
// Grove

import Foundation

nonisolated enum SubmoduleParser {

    /// Joins `.gitmodules` (names and URLs) with `git submodule status` (SHAs and state), keyed by path.
    static func parse(gitmodules: String, status: String) -> [SubmoduleInfo] {
        let declared = parseGitmodules(gitmodules)
        let states = parseStatus(status)
        let paths = declared.map(\.path) + states.keys.filter { path in !declared.contains { $0.path == path } }.sorted()
        return paths.map { path in
            let entry = declared.first { $0.path == path }
            let state = states[path]
            return SubmoduleInfo(name: entry?.name ?? path, path: path, url: entry?.url,
                                 sha: state?.sha, state: state?.state ?? .uninitialized)
        }
    }

    /// `[submodule "name"]` blocks with `path = …` and `url = …`.
    static func parseGitmodules(_ contents: String) -> [(name: String, path: String, url: String?)] {
        var result: [(name: String, path: String, url: String?)] = []
        var name: String?
        var path: String?
        var url: String?
        func flush() {
            if let name { result.append((name, path ?? name, url)) }
            path = nil
            url = nil
        }
        for raw in contents.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[submodule") {
                flush()
                name = line.split(separator: "\"").dropFirst().first.map(String.init)
            } else if let value = value(of: "path", in: line) {
                path = value
            } else if let value = value(of: "url", in: line) {
                url = value
            }
        }
        flush()
        return result
    }

    /// Lines of `git submodule status`: a state character, the SHA, the path, then an optional `(describe)`.
    static func parseStatus(_ output: String) -> [String: (sha: String, state: SubmoduleInfo.State)] {
        var result: [String: (sha: String, state: SubmoduleInfo.State)] = [:]
        for line in output.split(whereSeparator: \.isNewline) where line.count > 1 {
            let marker = line.first!
            let fields = line.dropFirst().split(separator: " ", maxSplits: 2)
            guard fields.count >= 2 else { continue }
            let state: SubmoduleInfo.State = switch marker {
            case "-": .uninitialized
            case "+": .modified
            case "U": .conflicted
            default: .upToDate
            }
            result[String(fields[1])] = (String(fields[0]), state)
        }
        return result
    }

    private static func value(of key: String, in line: String) -> String? {
        guard line.hasPrefix(key), let equals = line.firstIndex(of: "="),
              line[..<equals].trimmingCharacters(in: .whitespaces) == key else { return nil }
        return line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
    }
}
