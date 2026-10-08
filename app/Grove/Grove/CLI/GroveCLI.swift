// CLI/GroveCLI.swift
// Grove
//
// `grove` from Terminal: the bundled script runs Grove's own binary with `--grove-cli`, which handles the command
// without starting the app. Opening commands hand a grove://open URL to the running app; queries print and exit.

import AppKit
import Foundation
import GroveKit

enum GroveCLI {

    /// First argument the bundled script passes; anything else starts the app as usual.
    static let flag = "--grove-cli"

    enum Command: Equatable {
        /// Opens `path`'s repository in Grove, optionally on one view of it.
        case open(path: String, intent: RepositoryIntent?)
        case query(Query, path: String, json: Bool)
        case help
        case version
    }

    enum Query: String, CaseIterable {
        case stacks, branches, prs
    }

    struct UsageError: LocalizedError, Equatable {
        let message: String
        var errorDescription: String? { message }
    }

    static let usage = """
    Usage: grove [-C <path>] [<command>] [<args>]

    Open in Grove:
      grove [<folder>]          Open the repository containing <folder> (default: the current folder)
      grove history [<branch>]  Open History, filtered to <branch> when given
      grove blame <file>        Open Blame on <file>
      grove stack [<branch>]    Open the Stack tab on the stack holding <branch> (default: HEAD's)

    Print:
      grove stacks [--json]     Stacked branches with their pull requests and health
      grove branches [--json]   Local branches with upstream, ahead/behind and pull request
      grove prs [--json]        Open pull requests on the repository's host

    Options:
      -C <path>                 Run as if started in <path>
      -h, --help                Show this help
      --version                 Print Grove's version
    """

    // MARK: - Parsing

    /// Reads the arguments after `--grove-cli`; relative paths resolve against `directory`.
    static func parse(_ arguments: [String], in directory: String) throws -> Command {
        var arguments = arguments
        var directory = directory
        if arguments.first == "-C" {
            guard arguments.count > 1 else { throw UsageError(message: "-C needs a path") }
            directory = absolute(arguments[1], in: directory)
            arguments.removeFirst(2)
        }
        guard let first = arguments.first else { return .open(path: directory, intent: nil) }
        let rest = Array(arguments.dropFirst())
        switch first {
        case "-h", "--help", "help":
            return .help
        case "--version":
            return .version
        case "open":
            return .open(path: try single(rest, "open").map { absolute($0, in: directory) } ?? directory, intent: nil)
        case "history":
            return .open(path: directory, intent: .history(branch: try single(rest, "history")))
        case "stack":
            return .open(path: directory, intent: .stack(branch: try single(rest, "stack")))
        case "blame":
            guard let file = try single(rest, "blame") else { throw UsageError(message: "blame needs a file") }
            return .open(path: directory, intent: .blame(file: absolute(file, in: directory)))
        default:
            if let query = Query(rawValue: first) {
                let unknown = rest.filter { $0 != "--json" }
                guard unknown.isEmpty else { throw UsageError(message: "\(first) doesn't take \(unknown.joined(separator: " "))") }
                return .query(query, path: directory, json: rest.contains("--json"))
            }
            guard !first.hasPrefix("-"), rest.isEmpty else { throw UsageError(message: "Unknown command \(arguments.joined(separator: " "))") }
            // `grove <folder>`, as the command has always worked.
            return .open(path: absolute(first, in: directory), intent: nil)
        }
    }

    private static func single(_ arguments: [String], _ command: String) throws -> String? {
        guard arguments.count <= 1 else { throw UsageError(message: "\(command) takes one argument") }
        return arguments.first
    }

    static func absolute(_ path: String, in directory: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : URL(fileURLWithPath: directory).appendingPathComponent(expanded)
        return url.standardizedFileURL.path
    }

    // MARK: - Running

    /// Runs the command and exits; never returns to start the app.
    @MainActor
    static func run(_ arguments: [String]) -> Never {
        Task { @MainActor in
            exit(await execute(arguments))
        }
        dispatchMain()
    }

    @MainActor
    static func execute(_ arguments: [String]) async -> Int32 {
        do {
            switch try parse(arguments, in: FileManager.default.currentDirectoryPath) {
            case .help:
                print(usage)
            case .version:
                let info = Bundle.main.infoDictionary
                print("Grove \(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))")
            case .open(let path, let intent):
                try await open(path, intent: intent)
            case .query(let query, let path, let json):
                print(try await run(query, in: try await repositoryRoot(path), json: json))
            }
            return 0
        } catch let error as UsageError {
            FileHandle.standardError.write(Data("grove: \(error.message)\n\n\(usage)\n".utf8))
            return 2
        } catch {
            FileHandle.standardError.write(Data("grove: \(error.localizedDescription)\n".utf8))
            return 1
        }
    }

    @MainActor
    private static func open(_ path: String, intent: RepositoryIntent?) async throws {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue else {
            throw UsageError(message: "\(path) is not a folder")
        }
        if let intent {
            let root = try await repositoryRoot(path)
            try await check(intent, in: root)
        }
        let url = RepositoryURLRouter.url(opening: URL(fileURLWithPath: path).resolvingSymlinksInPath().path, intent: intent)
        guard NSWorkspace.shared.open(url) else { throw UsageError(message: "Couldn't hand \(path) to Grove") }
    }

    /// Fails here, in Terminal, rather than opening Grove on a branch or file that isn't there.
    private static func check(_ intent: RepositoryIntent, in root: String) async throws {
        let shell = GitShell(workingDirectory: URL(fileURLWithPath: root))
        switch intent {
        case .history(let branch?), .stack(let branch?):
            let local = try? await shell.runAllowingFailure(["rev-parse", "--verify", "--quiet", "refs/heads/\(branch)"])
            let remote = try? await shell.runAllowingFailure(["rev-parse", "--verify", "--quiet", "refs/remotes/\(branch)"])
            guard local?.isSuccess == true || remote?.isSuccess == true else { throw CLIError("No branch named \(branch)") }
        case .blame(let file):
            var isFolder: ObjCBool = false
            guard FileManager.default.fileExists(atPath: file, isDirectory: &isFolder), !isFolder.boolValue else {
                throw CLIError("No file at \(file)")
            }
            guard RepositoryURLRouter.relativePath(of: file, in: root) != nil else { throw CLIError("\(file) isn't in \(root)") }
        case .history(nil), .stack(nil):
            break
        }
    }

    static func repositoryRoot(_ path: String) async throws -> String {
        guard let root = await RepositoryURLRouter.repositoryRoot(containing: path) else { throw CLIError("\(path) isn't in a git repository") }
        return root
    }

    struct CLIError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }
}
