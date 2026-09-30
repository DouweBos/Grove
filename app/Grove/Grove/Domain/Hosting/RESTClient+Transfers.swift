// Domain/Hosting/RESTClient+Transfers.swift
// Grove
//
// Requests beyond plain JSON lists: lists wrapped in an object, and files the API hands out through a redirect.

import Foundation

extension RESTClient {

    /// Every page of a list that sits under `key` (`{"total_count": 3, "jobs": […]}`), following `Link` up to `maxPages`.
    func getPages(_ url: URL, key: String, maxPages: Int = 10,
                  cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) async throws -> [HostingJSON.Object] {
        var objects: [HostingJSON.Object] = []
        var next: URL? = url
        var pages = 0
        while let page = next, pages < maxPages {
            let (data, response) = try await send("GET", page, body: nil, accept: "application/json", cachePolicy: cachePolicy)
            objects += HostingJSON.object(data)?[key] as? [HostingJSON.Object] ?? []
            next = Self.nextPage(response.value(forHTTPHeaderField: "Link"))
            pages += 1
        }
        return objects
    }

    /// A file the API serves by redirecting to storage, e.g. a job log.
    func getRedirected(_ url: URL) async throws -> Data {
        let (data, response) = try await http.dataWithoutRedirect(for: authorized("GET", url, accept: "application/json"))
        guard let location = Self.redirectTarget(of: response) else {
            try check(response, data)
            return data
        }
        // The storage URL is signed; sending the token along leaks it to another host and gets the request refused.
        let (file, fileResponse) = try await http.data(for: URLRequest(url: location))
        guard (200..<300).contains(fileResponse.statusCode) else {
            throw HostingError.http(status: fileResponse.statusCode, message: Self.message(in: file))
        }
        return file
    }

    /// Like `getRedirected`, but streams the file to `destination`, e.g. an artifact's zip.
    func download(_ url: URL, to destination: URL) async throws {
        let (data, response) = try await http.dataWithoutRedirect(for: authorized("GET", url, accept: "application/json"))
        guard let location = Self.redirectTarget(of: response) else {
            try check(response, data)
            return try data.write(to: destination, options: .atomic)
        }
        let fileResponse = try await http.download(for: URLRequest(url: location), to: destination)
        guard (200..<300).contains(fileResponse.statusCode) else {
            throw HostingError.http(status: fileResponse.statusCode, message: "")
        }
    }

    static func redirectTarget(of response: HTTPURLResponse) -> URL? {
        guard (300..<400).contains(response.statusCode), let location = response.value(forHTTPHeaderField: "Location") else { return nil }
        return URL(string: location, relativeTo: response.url)?.absoluteURL
    }
}
