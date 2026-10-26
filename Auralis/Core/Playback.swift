import Foundation

enum PlaybackAction: String, Codable { case play, pause, nexttrack, previoustrack, seekto }

/// Facts from public MediaSession / HTMLMediaElement interfaces, never a stream or quality estimate.
struct PlaybackSnapshot: Codable, Equatable {
    let title: String
    let artist: String
    let album: String
    let artwork: String?
    let isPlaying: Bool
    let position: Double?
    let duration: Double?
    let rate: Double
    let actions: [String]
    let adVisible: Bool
    var validated: Bool {
        title.utf8.count <= 4096 && artist.utf8.count <= 4096 && album.utf8.count <= 4096
        && (artwork == nil || artwork!.utf8.count <= 8192)
        && (duration == nil || (duration!.isFinite && duration! > 0 && duration! <= 604800))
        && (position == nil || (position!.isFinite && position! >= 0 && position! <= (duration ?? 604800) + 1))
        && rate.isFinite && rate >= 0 && rate <= 16
        && actions.count <= 5 && actions.allSatisfy { PlaybackAction(rawValue: $0) != nil }
    }
    static func decode(_ object: Any) -> Self? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object), data.count <= 32_768,
              let result = try? JSONDecoder().decode(Self.self, from: data), result.validated else { return nil }
        return result
    }
    func elapsed(received: Date, now: Date) -> Double? {
        guard let position, let duration else { return nil }
        return min(duration, max(0, position + (isPlaying ? min(4, max(0, now.timeIntervalSince(received))) * rate : 0)))
    }
}
enum ProviderPolicy {
    static let musicURL = URL(string: "https://music.youtube.com/")!
    static let loginURL = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://music.youtube.com/")!
    static func isMusic(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host?.lowercased() == "music.youtube.com"
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }
    static func isHTTPS(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }
    static func hasSession(_ cookies: [HTTPCookie], now: Date = Date()) -> Bool {
        cookies.contains { $0.name == "SAPISID" && [".youtube.com", "youtube.com"].contains($0.domain.lowercased()) && ($0.expiresDate == nil || $0.expiresDate! > now) }
    }
}
enum ArtworkPolicy {
    static func permits(_ url: URL) -> Bool {
        ProviderPolicy.isHTTPS(url) && ["i.ytimg.com", "img.youtube.com", "lh3.googleusercontent.com", "yt3.ggpht.com", "yt3.googleusercontent.com"].contains(url.host?.lowercased() ?? "")
    }
}
enum ClockText {
    static func format(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "—:——" }
        let total = Int(min(seconds, 604800))
        return total >= 3600 ? String(format: "%d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60) : String(format: "%d:%02d", total / 60, total % 60)
    }
}
