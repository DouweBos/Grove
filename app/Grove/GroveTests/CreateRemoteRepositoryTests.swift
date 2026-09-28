// CreateRemoteRepositoryTests.swift
// GroveTests

import Foundation
import Testing
@testable import Grove

@MainActor
struct CreateRemoteRepositoryTests {

    private let account = CatalogAccount(id: "gh", kind: .github, host: "github.com", title: "me")

    private func browser() async -> RemoteRepositoriesViewModel {
        let viewModel = RemoteRepositoriesViewModel()
        let account = account
        viewModel.catalogSource = { [FixedCatalog(account: account, ownerLogins: ["me", "team"])] }
        await viewModel.reloadAccount()
        return viewModel
    }

    private func owner(_ login: String, isAccount: Bool = false, id: String? = nil) -> RemoteRepositoryOwner {
        RemoteRepositoryOwner(login: login, isAccount: isAccount, accountID: "x", serviceID: id)
    }

    // MARK: Requests

    @Test func githubCreatesUnderTheOrganizationOnlyWhenAsked() {
        let mine = NewRemoteRepository(owner: owner("me", isAccount: true), name: "app", description: "", isPrivate: true)
        #expect(GitHubCatalog.createArguments(mine) == ["repo", "create", "app", "--private"])
        let org = NewRemoteRepository(owner: owner("team"), name: "app", description: "Tools", isPrivate: false)
        #expect(GitHubCatalog.createArguments(org) == ["repo", "create", "team/app", "--public", "--description", "Tools"])
    }

    @Test func gitlabGroupsGetTheirNamespace() {
        let request = NewRemoteRepository(owner: owner("group/sub", id: "42"), name: "My App", description: "", isPrivate: true)
        #expect(GitLabCatalog.createFields(request) == ["name": "My App", "path": "my-app", "visibility": "private", "namespace_id": "42"])
        let personal = NewRemoteRepository(owner: owner("me", isAccount: true, id: "1"), name: "x", isPrivate: false)
        #expect(GitLabCatalog.createFields(personal)["namespace_id"] == nil)
    }

    @Test func bitbucketPostsToTheWorkspaceSlug() async throws {
        let http = FakeHTTPClient { _ in (200, #"{"full_name":"ws/new-repo","slug":"new-repo","is_private":true}"#) }
        let catalog = BitbucketCatalog(hostingAccount: HostingAccount(kind: .bitbucket, username: "me"),
                                       client: RESTClient(credentials: RESTCredentials(account: HostingAccount(kind: .bitbucket, username: "me"),
                                                                                       secret: "pw"), http: http))
        let created = try await catalog.createRepository(NewRemoteRepository(owner: owner("ws"), name: "New-Repo", description: "D"))
        #expect(created.nameWithOwner == "ws/new-repo")
        let request = try #require(http.requests.first)
        #expect(request.httpMethod == "POST" && request.url?.path == "/2.0/repositories/ws/new-repo")
        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["scm"] as? String == "git" && body["is_private"] as? Bool == true && body["description"] as? String == "D")
    }

    @Test func azurePostsIntoTheProject() async throws {
        let response = #"{"name":"svc","project":{"name":"Proj"},"remoteUrl":"https://org@dev.azure.com/org/Proj/_git/svc"}"#
        let http = FakeHTTPClient { _ in (201, response) }
        let hosting = HostingAccount(kind: .azureDevOps, username: "me", organization: "org")
        let catalog = AzureDevOpsCatalog(hostingAccount: hosting, client: RESTClient(credentials: RESTCredentials(account: hosting, secret: "p"),
                                                                                     http: http))
        #expect(!catalog.supportsVisibilityAndDescription)
        let created = try await catalog.createRepository(NewRemoteRepository(owner: owner("Proj", id: "p-1"), name: "svc"))
        #expect(created.httpsCloneURL == "https://dev.azure.com/org/Proj/_git/svc")
        let request = try #require(http.requests.first)
        #expect(request.url?.path == "/org/Proj/_apis/git/repositories")
        let body = try #require(request.httpBody.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect((body["project"] as? [String: Any])?["id"] as? String == "p-1")
    }

    // MARK: Flow

    @Test func nameRulesMatchWhatServicesAccept() async {
        let browser = await browser()
        browser.beginCreating()
        let creation = try? #require(browser.creation)
        creation?.setName("good.name_1-x")
        #expect(creation?.isNameValid == true)
        creation?.setName("has space")
        #expect(creation?.isNameValid == false)
        creation?.setName("..")
        #expect(creation?.canCreate == false)
    }

    @Test func createdRepositoryIsListedAndSelected() async throws {
        let browser = await browser()
        let team = try #require(browser.owners.last)
        browser.beginCreating(owner: team)
        let creation = try #require(browser.creation)
        #expect(creation.owner?.login == "team")
        creation.setName("tool")
        await creation.create()
        guard case .created(let repository) = creation.phase else { Issue.record("not created"); return }
        #expect(repository.nameWithOwner == "team/tool")
        #expect(browser.repositories(of: team).first?.name == "tool")
        #expect(browser.selected?.id == repository.id)
    }

    @Test func failedCreateStaysEditable() async throws {
        let browser = await browser()
        browser.beginCreating()
        let creation = try #require(browser.creation)
        creation.setName("taken")
        await creation.create()
        #expect(creation.phase == .editing)
        #expect(creation.errorMessage?.contains("already exists") == true)
    }

    @Test func addsTheSSHURLAsARemoteOfTheChosenRepository() async throws {
        let browser = await browser()
        var added: [String] = []
        browser.beginCreating(targets: [.init(path: "/tmp/a", name: "a"), .init(path: "/tmp/b", name: "b")],
                              preferredTarget: "/tmp/b") { path, name, url in added = [path, name, url] }
        let creation = try #require(browser.creation)
        #expect(!creation.canAddRemote)
        creation.setName("tool")
        await creation.create()
        creation.setRemoteName("github")
        await creation.addAsRemote()
        #expect(added == ["/tmp/b", "github", "git@github.com:me/tool.git"])
        #expect(creation.addedRemote == "github" && !creation.canAddRemote)
    }
}
