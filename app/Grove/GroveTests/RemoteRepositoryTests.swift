// RemoteRepositoryTests.swift
// GroveTests

import Foundation
@testable import GroveKit
import Testing
@testable import Grove

struct RemoteRepositoryTests {

    @Test func remoteURLsNormalizeToTheSameKey() {
        let key = "github.com/plexinc/react-native-client"
        #expect(RemoteURLKey.make("git@github.com:plexinc/react-native-client.git") == key)
        #expect(RemoteURLKey.make("https://DouweBos@github.com/plexinc/react-native-client.git") == key)
        #expect(RemoteURLKey.make("https://github.com/plexinc/react-native-client") == key)
        #expect(RemoteURLKey.make("ssh://git@github.com/plexinc/React-Native-Client/") == key)
        #expect(RemoteURLKey.make("ssh://git@github.com:22/plexinc/react-native-client.git") == key)
        #expect(RemoteURLKey.make("/Users/me/local/path") == nil)
    }

    @Test func githubRepositoriesParse() throws {
        let json = """
        [{"name":"new","full_name":"me/new","owner":{"login":"me"},"description":"Fresh","private":true,"fork":false,
          "archived":false,"pushed_at":"2026-09-28T10:45:51Z","html_url":"https://github.com/me/new","ssh_url":"git@github.com:me/new.git",
          "clone_url":"https://github.com/me/new.git","default_branch":"main","language":"Swift"},
         {"name":"old","full_name":"me/old","owner":{"login":"me"},"description":"","private":false,"fork":true,
          "archived":true,"pushed_at":"2024-01-01T00:00:00Z","html_url":"https://github.com/me/old","ssh_url":"git@github.com:me/old.git",
          "default_branch":null,"language":null}]
        """
        let repos = HostingJSON.objects(json).compactMap { GitHubParser.repository($0, host: "github.com") }
        #expect(repos.map(\.name) == ["new", "old"])
        #expect(repos[0].defaultBranch == "main" && repos[0].language == "Swift" && repos[0].isPrivate)
        #expect(repos[1].description == nil && repos[1].isFork && repos[1].isArchived)
        #expect(repos[0].httpsCloneURL == "https://github.com/me/new.git")
        #expect(repos[0].matchKey == "github.com/me/new")
    }

    @MainActor
    @Test func localClonesAreFoundFromBookmarkRemotes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("grove-remote-\(UUID().uuidString)")
        let gitDir = root.appendingPathComponent("app/.git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "[remote \"origin\"]\n\turl = git@github.com:me/new.git\n".write(to: gitDir.appendingPathComponent("config"),
                                                                             atomically: true, encoding: .utf8)
        let bookmark = RepositoryBookmarkData(id: UUID(), path: root.appendingPathComponent("app").path, displayName: "app",
                                              addedDate: Date(), lastOpenedDate: nil, sortOrder: 0, groupID: nil)
        let viewModel = RemoteRepositoriesViewModel()
        viewModel.indexLocalClones(bookmarks: [bookmark])
        #expect(viewModel.localClones["github.com/me/new"] == bookmark.path)
    }
}
