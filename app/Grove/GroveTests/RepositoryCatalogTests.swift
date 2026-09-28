// RepositoryCatalogTests.swift
// GroveTests

import Foundation
import Testing
@testable import Grove

/// A catalog with fixed owners and repositories.
struct FixedCatalog: RepositoryCatalog {
    let account: CatalogAccount
    let ownerLogins: [String]
    var fails = false

    func owners() async throws -> [RemoteRepositoryOwner] {
        if fails { throw HostingError.notSignedIn(account.kind) }
        return ownerLogins.enumerated().map { RemoteRepositoryOwner(login: $1, isAccount: $0 == 0, accountID: account.id) }
    }

    func repositories(of owner: RemoteRepositoryOwner) async throws -> [RemoteRepository] {
        [RemoteRepository(nameWithOwner: "\(owner.login)/app", name: "app", owner: owner.login, description: nil, isPrivate: true,
                          isFork: false, isArchived: false, updatedAt: nil, webURL: "https://\(account.host)/\(owner.login)/app",
                          sshURL: "", defaultBranch: "main", language: nil, service: account.kind)]
    }
}

@MainActor
struct RepositoryCatalogTests {

    @Test func eachAccountGetsItsOwnSection() async {
        let viewModel = RemoteRepositoriesViewModel()
        let github = CatalogAccount(id: "gh", kind: .github, host: "github.com", title: "me")
        let bitbucket = CatalogAccount(id: "bb", kind: .bitbucket, host: "bitbucket.org", title: "me")
        let azure = CatalogAccount(id: "az", kind: .azureDevOps, host: "dev.azure.com/org", title: "org")
        viewModel.catalogSource = {
            [FixedCatalog(account: github, ownerLogins: ["me", "team"]), FixedCatalog(account: bitbucket, ownerLogins: ["me"]),
             FixedCatalog(account: azure, ownerLogins: [], fails: true)]
        }
        await viewModel.reloadAccount()
        #expect(viewModel.account == .signedIn)
        #expect(viewModel.sections.map(\.id) == ["gh", "bb", "az"])
        #expect(viewModel.sections[2].failure != nil)
        // The same login on two services stays two owners, and the first one loads straight away.
        #expect(Set(viewModel.owners.map(\.id)).count == 3)
        #expect(viewModel.repositories(of: viewModel.owners[0]).first?.service == .github)
        await viewModel.load(viewModel.owners[2])
        #expect(viewModel.repositories(of: viewModel.owners[2]).first?.service == .bitbucket)
    }

    @Test func noAccountsExplainsWhatToSetUp() async {
        let viewModel = RemoteRepositoriesViewModel()
        viewModel.catalogSource = { [] }
        await viewModel.reloadAccount()
        if case .unavailable = viewModel.account {} else { Issue.record("expected unavailable") }
    }

    @Test func parsesGitLabProjects() throws {
        let raw = try #require(HostingJSON.objects("""
        [{"path_with_namespace":"group/app","path":"app","namespace":{"full_path":"group"},"description":"","visibility":"private",
          "archived":false,"last_activity_at":"2026-09-01T10:00:00Z","web_url":"https://gitlab.com/group/app",
          "ssh_url_to_repo":"git@gitlab.com:group/app.git","http_url_to_repo":"https://gitlab.com/group/app.git","default_branch":"main"}]
        """).first)
        let repo = try #require(CatalogParser.gitlabProject(raw))
        #expect(repo.nameWithOwner == "group/app" && repo.isPrivate && repo.description == nil && repo.service == .gitlab)
        #expect(repo.httpsCloneURL == "https://gitlab.com/group/app.git" && repo.matchKey == "gitlab.com/group/app")
    }

    @Test func parsesBitbucketRepositoriesWithoutTheCloneUser() throws {
        let raw: [String: Any] = [
            "full_name": "ws/repo", "slug": "repo", "is_private": true, "updated_on": "2026-09-01T10:00:00.000000+00:00",
            "mainbranch": ["name": "develop"], "language": "swift",
            "links": ["html": ["href": "https://bitbucket.org/ws/repo"],
                      "clone": [["name": "https", "href": "https://me@bitbucket.org/ws/repo.git"],
                                ["name": "ssh", "href": "git@bitbucket.org:ws/repo.git"]]]
        ]
        let repo = try #require(CatalogParser.bitbucketRepository(raw))
        #expect(repo.httpsCloneURL == "https://bitbucket.org/ws/repo.git" && repo.sshURL == "git@bitbucket.org:ws/repo.git")
        #expect(repo.defaultBranch == "develop" && repo.owner == "ws" && repo.service == .bitbucket)
    }

    @Test func parsesAzureRepositories() throws {
        let raw: [String: Any] = [
            "name": "repo", "webUrl": "https://dev.azure.com/org/proj/_git/repo", "remoteUrl": "https://org@dev.azure.com/org/proj/_git/repo",
            "sshUrl": "git@ssh.dev.azure.com:v3/org/proj/repo", "defaultBranch": "refs/heads/main",
            "project": ["name": "proj", "visibility": "private"]
        ]
        let repo = try #require(CatalogParser.azureRepository(raw, organization: "org"))
        #expect(repo.nameWithOwner == "org/proj/repo" && repo.defaultBranch == "main" && repo.isPrivate)
        #expect(repo.httpsCloneURL == "https://dev.azure.com/org/proj/_git/repo")
    }
}
