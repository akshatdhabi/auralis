import Foundation

struct BrowseLink: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let kind: String
    var valid: Bool { !id.isEmpty && id.utf8.count <= 100 && !title.isEmpty && title.utf8.count <= 1000 && ["artist", "album", "playlist", "play", "shuffle", "item"].contains(kind) }
}
struct BrowseItem: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let artwork: String?
    let kind: String
    var links: [BrowseLink]? = nil
    var valid: Bool {
        !id.isEmpty && id.utf8.count <= 100 && !title.isEmpty && title.utf8.count <= 1000
        && subtitle.utf8.count <= 2000 && (artwork == nil || artwork!.utf8.count <= 8192)
        && ["song", "album", "playlist", "artist", "item"].contains(kind)
        && (links == nil || (links!.count <= 8 && links!.allSatisfy(\.valid)))
    }
}
struct BrowseDetail: Codable, Equatable {
    let title: String
    let subtitle: String
    let artwork: String?
    let kind: String
    let actions: [BrowseLink]
    var valid: Bool { title.utf8.count <= 1000 && subtitle.utf8.count <= 2000 && ["artist", "album", "playlist", "item"].contains(kind) && (artwork == nil || artwork!.utf8.count <= 8192) && actions.count <= 12 && actions.allSatisfy(\.valid) }
}
struct QueueEntry: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let artwork: String?
    let current: Bool
    var valid: Bool { !id.isEmpty && id.utf8.count <= 100 && !title.isEmpty && title.utf8.count <= 1000 && subtitle.utf8.count <= 2000 && (artwork == nil || artwork!.utf8.count <= 8192) }
}
struct QueueSnapshot: Codable, Equatable {
    let items: [QueueEntry]
    let links: [BrowseLink]
    let canRadio: Bool
    var valid: Bool { items.count <= 80 && Set(items.map(\.id)).count == items.count && items.allSatisfy(\.valid) && links.count <= 8 && links.allSatisfy(\.valid) }
    static func decode(_ object: Any) -> Self? {
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object), data.count <= 300_000,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.valid else { return nil }; return value
    }
}
struct BrowseShelf: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let items: [BrowseItem]
}
struct BrowseSnapshot: Codable, Equatable {
    let path: String
    let heading: String
    let shelves: [BrowseShelf]
    let library: [BrowseItem]
    var detail: BrowseDetail? = nil
    var route: String? = nil
    var valid: Bool {
        path.utf8.count <= 2000 && (route == nil || route!.utf8.count <= 4000) && heading.utf8.count <= 1000 && shelves.count <= 12 && library.count <= 8
        && shelves.allSatisfy { $0.id.utf8.count <= 100 && $0.title.utf8.count <= 1000 && $0.items.count <= 24 && $0.items.allSatisfy(\.valid) }
        && library.allSatisfy(\.valid)
        && (detail == nil || detail!.valid)
    }
    static func decode(_ object: Any) -> Self? {
        guard JSONSerialization.isValidJSONObject(object), let data = try? JSONSerialization.data(withJSONObject: object), data.count <= 300_000,
              let value = try? JSONDecoder().decode(Self.self, from: data), value.valid else { return nil }
        return value
    }
}
enum BrowseDestination: String, CaseIterable { case home, explore, library }
