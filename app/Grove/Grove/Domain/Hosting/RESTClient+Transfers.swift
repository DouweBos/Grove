// Domain/Hosting/RESTClient+Transfers.swift
// Grove
//
// Requests beyond plain JSON lists: lists wrapped in an object, as the Actions API returns them.

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
}
