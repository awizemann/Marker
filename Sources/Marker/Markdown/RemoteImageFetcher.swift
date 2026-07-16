//
//  RemoteImageFetcher.swift
//  Marker — (ex TrapperKeeperCore) Markdown (Images v2, t-c6f28efb)
//
//  Fetches remote (`http(s)`) images for inline rendering — the app's only outbound network use. Off
//  the main actor, timeout- + size-capped, with a small in-process cache so re-resolving the same doc
//  doesn't refetch. Never throws: a failed fetch renders the placeholder (see ImageAttachment).
//
//  Privacy: fetching a remote image tells that host the document was opened. It happens only for an
//  explicit `![](https://…)` the user wrote or inserted — never speculatively.
//

import Foundation

public actor RemoteImageFetcher {
    public static let shared = RemoteImageFetcher()

    private var cache: [String: Data] = [:]
    private let maxBytes = 25_000_000

    public init() {}

    /// The bytes for a remote image URL, or nil (bad url / non-http(s) / non-2xx / too big / offline).
    public func data(for urlString: String) async -> Data? {
        if let cached = cache[urlString] { return cached }
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        let request = URLRequest(url: url, timeoutInterval: 15)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  data.count <= maxBytes else { return nil }
            if cache.count > 64 { cache.removeAll() }   // crude bound; images per doc are few
            cache[urlString] = data
            return data
        } catch {
            return nil
        }
    }
}
