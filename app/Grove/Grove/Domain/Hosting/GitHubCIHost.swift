// Domain/Hosting/GitHubCIHost.swift
// Grove
//
// GitHub Actions over REST: `{api}/repos/{owner}/{name}/actions/…`.

import Foundation

nonisolated struct GitHubCIHost: CIHost, GitHubRepositoryAPI {
    let location: RemoteLocation
    let client: RESTClient
    var kind: HostingServiceKind { .github }

    // GitHub lets responses be cached for a minute, which a poll every few seconds would keep re-reading.
    private static let fresh = URLRequest.CachePolicy.reloadIgnoringLocalCacheData

    func workflows() async throws -> [CIWorkflow] {
        try await client.getPages(try url("/actions/workflows?per_page=100"), key: "workflows").compactMap(GitHubCIParser.workflow)
    }

    func runs(_ query: CIRunQuery) async throws -> [CIRun] {
        try await client.getPages(try url(Self.runsPath(query)), key: "workflow_runs", maxPages: 1, cachePolicy: Self.fresh)
            .compactMap(GitHubCIParser.run)
    }

    func run(id: Int) async throws -> CIRun {
        let data = try await client.get(try url("/actions/runs/\(id)"), cachePolicy: Self.fresh)
        guard let run = HostingJSON.object(data).flatMap(GitHubCIParser.run) else {
            throw HostingError.unsupported("GitHub returned no run \(id).")
        }
        return run
    }

    func jobs(runID: Int) async throws -> [CIJob] {
        try await client.getPages(try url("/actions/runs/\(runID)/jobs?filter=latest&per_page=100"), key: "jobs", cachePolicy: Self.fresh)
            .compactMap(GitHubCIParser.job)
    }

    func log(jobID: Int) async throws -> String {
        String(decoding: try await client.getRedirected(try url("/actions/jobs/\(jobID)/logs")), as: UTF8.self)
    }

    func artifacts(runID: Int) async throws -> [CIArtifact] {
        try await client.getPages(try url("/actions/runs/\(runID)/artifacts?per_page=100"), key: "artifacts", cachePolicy: Self.fresh)
            .compactMap(GitHubCIParser.artifact)
    }

    func downloadArtifact(id: Int, to destination: URL) async throws {
        try await client.download(try url("/actions/artifacts/\(id)/zip"), to: destination)
    }

    func rerun(runID: Int, failedOnly: Bool) async throws {
        try await client.send("POST", try url("/actions/runs/\(runID)/\(failedOnly ? "rerun-failed-jobs" : "rerun")"), json: nil)
    }

    func cancel(runID: Int) async throws {
        try await client.send("POST", try url("/actions/runs/\(runID)/cancel"), json: nil)
    }

    func workflowFile(path: String, ref: String) async throws -> String {
        let encoded = path.split(separator: "/").map { Self.queryValue(String($0)) }.joined(separator: "/")
        let data = try await client.get(try url("/contents/\(encoded)?ref=\(Self.queryValue(ref))"), accept: "application/vnd.github.raw+json",
                                        cachePolicy: Self.fresh)
        return String(decoding: data, as: UTF8.self)
    }

    func dispatch(_ dispatch: CIDispatch) async throws {
        try await client.send("POST", try url("/actions/workflows/\(dispatch.workflowID)/dispatches"),
                              json: ["ref": dispatch.ref, "inputs": dispatch.inputs])
    }

    /// A workflow filter is part of the path; branch and status are query items.
    static func runsPath(_ query: CIRunQuery) -> String {
        var items = ["per_page=\(query.limit)"]
        if let branch = query.branch { items.append("branch=\(queryValue(branch))") }
        if let status = query.status { items.append("status=\(GitHubCIParser.statusParameter(status))") }
        return (query.workflowID.map { "/actions/workflows/\($0)/runs" } ?? "/actions/runs") + "?" + items.joined(separator: "&")
    }

    /// Stricter than `URLComponents`, which leaves `+` and `&` of a branch name for the server to misread.
    static func queryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~/"))) ?? value
    }
}
