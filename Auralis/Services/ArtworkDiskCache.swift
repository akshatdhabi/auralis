import Foundation
import CryptoKit

/// Only validated, cookie-free image bytes are stored. URLs become hashes, not filenames.
/// This actor keeps file reads, atomic writes and pruning off the main actor.
actor ArtworkDiskCache {
    static let shared = ArtworkDiskCache(directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("studio.auralis/Artwork-v1", isDirectory: true))
    private let directory: URL?
    private let byteLimit: Int
    private let countLimit: Int
    private let lifetime: TimeInterval
    init(directory: URL?, byteLimit: Int = 96 * 1024 * 1024, countLimit: Int = 512, lifetime: TimeInterval = 7 * 24 * 60 * 60) {
        self.directory = directory; self.byteLimit = max(0, byteLimit); self.countLimit = max(0, countLimit); self.lifetime = max(0, lifetime)
    }
    private func file(_ url: URL) -> URL? {
        guard ArtworkPolicy.permits(url) else { return nil }
        let key = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent(key).appendingPathExtension("image")
    }
    func data(for url: URL, now: Date = Date()) -> Data? {
        guard let path = file(url), let attributes = try? FileManager.default.attributesOfItem(atPath: path.path),
              let modified = attributes[.modificationDate] as? Date,
              let size = attributes[.size] as? Int else { return nil }
        guard now.timeIntervalSince(modified) < lifetime, size > 0, size <= min(8_000_000, byteLimit) else {
            try? FileManager.default.removeItem(at: path); return nil
        }
        return try? Data(contentsOf: path)
    }
    func remove(_ url: URL) { if let path = file(url) { try? FileManager.default.removeItem(at: path) } }
    func store(_ data: Data, for url: URL) {
        guard !data.isEmpty, data.count <= min(8_000_000, byteLimit), let directory, let path = file(url) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: path, options: .atomic)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
                .filter { $0.pathExtension == "image" }
                .compactMap { url -> (URL, Int, Date)? in
                    guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                          values.isRegularFile == true, let size = values.fileSize, let date = values.contentModificationDate else { return nil }
                    return (url, size, date)
                }.sorted { $0.2 < $1.2 }
            var bytes = files.reduce(0) { $0 + $1.1 }
            var count = files.count
            for (url, size, date) in files {
                if bytes > byteLimit || count > countLimit || Date().timeIntervalSince(date) >= lifetime {
                    try FileManager.default.removeItem(at: url); bytes -= size; count -= 1
                }
            }
        } catch { /* Cache failure must never prevent first-party artwork loading. */ }
    }
}
