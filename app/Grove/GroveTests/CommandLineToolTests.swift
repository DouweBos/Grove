// CommandLineToolTests.swift
// GroveTests
//
// The arguments `grove` takes and the URLs it turns into.

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

@Suite(.serialized)
struct CommandLineToolTests {

    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grove-cli-\(UUID().uuidString)").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    // MARK: - Arguments

    @Test func parsesOpeningCommands() throws {
        #expect(try GroveCLI.parse([], in: "/repo") == .open(path: "/repo", intent: nil))
        #expect(try GroveCLI.parse(["sub/dir"], in: "/repo") == .open(path: "/repo/sub/dir", intent: nil))
        #expect(try GroveCLI.parse(["open", "../other"], in: "/repo") == .open(path: "/other", intent: nil))
        #expect(try GroveCLI.parse(["history"], in: "/repo") == .open(path: "/repo", intent: .history(branch: nil)))
        #expect(try GroveCLI.parse(["history", "feature/x"], in: "/repo") == .open(path: "/repo", intent: .history(branch: "feature/x")))
        #expect(try GroveCLI.parse(["stack", "a"], in: "/repo") == .open(path: "/repo", intent: .stack(branch: "a")))
        #expect(try GroveCLI.parse(["blame", "src/a.swift"], in: "/repo") == .open(path: "/repo", intent: .blame(file: "/repo/src/a.swift")))
        #expect(try GroveCLI.parse(["-C", "/elsewhere", "history"], in: "/repo") == .open(path: "/elsewhere", intent: .history(branch: nil)))
    }

    @Test func parsesQueriesAndRejectsTheRest() throws {
        #expect(try GroveCLI.parse(["stacks"], in: "/repo") == .query(.stacks, path: "/repo", json: false))
        #expect(try GroveCLI.parse(["prs", "--json"], in: "/repo") == .query(.prs, path: "/repo", json: true))
        #expect(try GroveCLI.parse(["--help"], in: "/repo") == .help)
        #expect(throws: GroveCLI.UsageError.self) { try GroveCLI.parse(["blame"], in: "/repo") }
        #expect(throws: GroveCLI.UsageError.self) { try GroveCLI.parse(["history", "a", "b"], in: "/repo") }
        #expect(throws: GroveCLI.UsageError.self) { try GroveCLI.parse(["branches", "--yaml"], in: "/repo") }
        #expect(throws: GroveCLI.UsageError.self) { try GroveCLI.parse(["--frobnicate"], in: "/repo") }
    }

    // MARK: - URLs

    @Test func intentsSurviveTheURL() throws {
        let intents: [RepositoryIntent?] = [nil, .history(branch: nil), .history(branch: "a&b=c+d é"), .stack(branch: "x"),
                                            .blame(file: "/tmp/my repo/a#b.swift")]
        for intent in intents {
            let url = RepositoryURLRouter.url(opening: "/tmp/my repo & co", intent: intent)
            #expect(RepositoryURLRouter.path(from: url) == "/tmp/my repo & co")
            #expect(RepositoryURLRouter.intent(from: url) == intent)
        }
    }

    @Test func routerAcceptsOnlyOpenURLsWithAbsolutePaths() throws {
        #expect(RepositoryURLRouter.path(from: try #require(URL(string: "grove://open?path=%2Ftmp%2Fa%20b"))) == "/tmp/a b")
        #expect(RepositoryURLRouter.path(from: try #require(URL(string: "grove://open?path=relative"))) == nil)
        #expect(RepositoryURLRouter.path(from: try #require(URL(string: "grove://delete?path=%2Ftmp"))) == nil)
        #expect(RepositoryURLRouter.path(from: try #require(URL(string: "https://open?path=%2Ftmp"))) == nil)
        #expect(RepositoryURLRouter.intent(from: try #require(URL(string: "grove://open?path=%2Ftmp&view=blame&file=a"))) == nil)
        #expect(RepositoryURLRouter.intent(from: try #require(URL(string: "grove://open?path=%2Ftmp&view=delete"))) == nil)
    }

    @Test func blamePathsAreRelativeToTheRepository() {
        #expect(RepositoryURLRouter.relativePath(of: "\(root.path)/repo/src/a.swift", in: "\(root.path)/repo") == "src/a.swift")
        #expect(RepositoryURLRouter.relativePath(of: "\(root.path)/repository/a.swift", in: "\(root.path)/repo") == nil)
    }

    @Test func subfolderResolvesToRepositoryRoot() async throws {
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("src/deep"), withIntermediateDirectories: true)
        #expect(try run("/usr/bin/git", arguments: ["init", "-q", repo.path]).status == 0)
        let resolved = await RepositoryURLRouter.repositoryRoot(containing: repo.appendingPathComponent("src/deep").path)
        #expect(resolved.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == repo.resolvingSymlinksInPath().path)
        #expect(await RepositoryURLRouter.repositoryRoot(containing: root.path) == nil)
    }

    private func run(_ executable: String, arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory()]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
