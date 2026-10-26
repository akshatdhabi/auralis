import Foundation

enum TextAtmosphere: String, CaseIterable, Identifiable {
    case track = "Track typography"
    case lyrics = "Lyrics"
    case artist = "Artist story"
    case off = "No background text"
    var id: String { rawValue }
}
struct LyricsSnapshot: Codable, Equatable {
    let title: String
    let lines: [String]
    let source: String
    var valid: Bool { title.utf8.count <= 4096 && lines.count <= 100 && lines.allSatisfy { $0.utf8.count <= 1200 } && source.utf8.count <= 300 }
    static func decode(_ object: Any) -> Self? {
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object), data.count <= 40_000,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.valid else { return nil }; return value
    }
}
struct ArtistStory: Equatable {
    let artist: String
    let article: String
    let text: String
    let url: URL
    static func permitsSource(_ url: URL) -> Bool {
        ProviderPolicy.isHTTPS(url) && url.host?.lowercased() == "en.wikipedia.org" && url.path.hasPrefix("/wiki/")
    }
    static func decode(_ data: Data, artist: String) -> Self? {
        guard data.count <= 262_144,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = root["query"] as? [String: Any], let pages = query["pages"] as? [[String: Any]] else { return nil }
        func key(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespacesAndNewlines) }
        let expected = key(artist)
        guard !expected.isEmpty else { return nil }
        for page in pages {
            guard page["missing"] == nil,
                  (page["pageprops"] as? [String: Any])?["disambiguation"] == nil,
                  let title = page["title"] as? String, let extract = page["extract"] as? String,
                  let address = page["fullurl"] as? String, let url = URL(string: address), permitsSource(url), extract.count > 40 else { continue }
            let base = title.replacingOccurrences(of: #" \((band|musician|singer|rapper|musical group)\)$"#, with: "", options: .regularExpression)
            guard key(base) == expected, ["band", "musician", "singer", "rapper", "musical", "recording", "music"].contains(where: extract.lowercased().contains) else { continue }
            return Self(artist: artist, article: title, text: String(extract.prefix(1800)), url: url)
        }
        return nil
    }
}

enum PanoramaMath {
    static func clamp(_ offset: CGFloat, viewport: CGFloat, extent: CGFloat) -> CGFloat { min(max(0, offset), max(0, extent - viewport)) }
    static func nearby(origin: CGFloat, width: CGFloat, offset: CGFloat, viewport: CGFloat) -> Bool {
        origin + width > offset - viewport * 0.35 && origin < offset + viewport * 1.35
    }
}

/// Decorative modes; none inspect an audio signal.
enum AmbientMotion: String, CaseIterable { case aurora = "Aurora", ribbons = "Ribbons", still = "Still" }
