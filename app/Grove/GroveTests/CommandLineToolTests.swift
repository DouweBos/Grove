// CommandLineToolTests.swift
// GroveTests
//
// The `grove` script, installed into a temp folder and run with a stand-in `open`, and the URLs it produces.

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

    @Test func installWritesAnExecutableScript() throws {
        let installed = try CommandLineTool.install(in: root.appendingPathComponent("bin"))
        #expect(FileManager.default.isExecutableFile(atPath: installed.path))
        #expect(try String(contentsOf: installed, encoding: .utf8) == CommandLineTool.script)
    }

    @Test func scriptOpensAnEncodedGroveURL() throws {
        let installed = try CommandLineTool.install(in: root.appendingPathComponent("bin"))
        // A stand-in `open` records the URL instead of launching anything.
        let fakes = root.appendingPathComponent("fakes")
        try FileManager.default.createDirectory(at: fakes, withIntermediateDirectories: true)
        let recorded = root.appendingPathComponent("opened.txt")
        try Data("#!/bin/sh\nprintf '%s' \"$1\" > '\(recorded.path)'\n".utf8).write(to: fakes.appendingPathComponent("open"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakes.appendingPathComponent("open").path)
        let folder = root.appendingPathComponent("My Repo é")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let status = try run(installed.path, arguments: [folder.path], path: "\(fakes.path):/usr/bin:/bin")

        #expect(status == 0)
        let url = try #require(URL(string: try String(contentsOf: recorded, encoding: .utf8)))
        #expect(RepositoryURLRouter.path(from: url) == folder.path)
    }

    @Test func scriptRejectsMissingFolder() throws {
        let installed = try CommandLineTool.install(in: root.appendingPathComponent("bin"))
        #expect(try run(installed.path, arguments: [root.appendingPathComponent("nope").path], path: "/usr/bin:/bin") == 1)
    }

    @Test func routerAcceptsOnlyOpenURLsWithAbsolutePaths() throws {
        #expect(RepositoryURLRouter.path(from: try #require(URL(string: "grove://open?path=%2Ftmp%2Fa%20b"))) == "/tmp/a b")
        #expect(RepositoryURLRouter.path(from: try #require(URL(string: "grove://open?path=relative"))) == nil)
        #expect(RepositoryURLRouter.path(from: try #require(URL(string: "grove://delete?path=%2Ftmp"))) == nil)
        #expect(RepositoryURLRouter.path(from: try #require(URL(string: "https://open?path=%2Ftmp"))) == nil)
    }

    @Test func subfolderResolvesToRepositoryRoot() async throws {
        let repo = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("src/deep"), withIntermediateDirectories: true)
        #expect(try run("/usr/bin/git", arguments: ["init", "-q", repo.path], path: "/usr/bin:/bin") == 0)
        let resolved = await RepositoryURLRouter.repositoryRoot(containing: repo.appendingPathComponent("src/deep").path)
        #expect(resolved.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } == repo.resolvingSymlinksInPath().path)
        #expect(await RepositoryURLRouter.repositoryRoot(containing: root.path) == nil)
    }

    private func run(_ executable: String, arguments: [String], path: String) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ["PATH": path, "HOME": NSHomeDirectory()]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}
