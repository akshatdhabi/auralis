import Foundation

/// On-demand, public encyclopaedia context. Never sends the track, account,
/// cookies or listening history. No model invents a biography or resolves names.
actor ArtistStoryService {
    private var cache: [String: ArtistStory] = [:]
    func story(for artist: String) async throws -> ArtistStory? {
        guard !artist.isEmpty, artist.count <= 200 else { return nil }
        if let cached = cache[artist] { return cached }
        let titles = [artist, artist + " (band)", artist + " (musician)", artist + " (singer)", artist + " (rapper)"]
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"), .init(name: "formatversion", value: "2"),
            .init(name: "prop", value: "extracts|info|pageprops"), .init(name: "titles", value: titles.joined(separator: "|")),
            .init(name: "redirects", value: "1"), .init(name: "exintro", value: "1"), .init(name: "explaintext", value: "1"),
            .init(name: "exsentences", value: "4"), .init(name: "inprop", value: "url")
        ]
        guard let url = components.url else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 8; configuration.timeoutIntervalForResource = 12
        let delegate = WikipediaRedirectPolicy()
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.setValue("Auralis/0.5 (local macOS music client; artist context)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.mimeType == "application/json", response.expectedContentLength <= 262_144 else { return nil }
        // This infrequent text lookup is bounded while receiving and runs on an
        // actor separate from UI rendering. Artwork uses its chunked image loader.
        var data = Data(); data.reserveCapacity(16_384)
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 262_144 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        let value = ArtistStory.decode(data, artist: artist)
        if let value { if cache.count >= 20 { cache.removeAll(keepingCapacity: true) }; cache[artist] = value }
        return value
    }
}
private final class WikipediaRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, ProviderPolicy.isHTTPS(url), url.host == "en.wikipedia.org" else { completionHandler(nil); return }
        completionHandler(request)
    }
}
