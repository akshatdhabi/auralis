import AppKit
import Foundation

@MainActor final class BrowseArtworkCache {
    static let shared = BrowseArtworkCache()
    private let cache = NSCache<NSURL, NSImage>()
    private let loader = ArtworkService()
    private var pending: [URL: Task<NSImage?, Never>] = [:]
    private var failures: [URL: Date] = [:]
    private let gate = ArtworkGate()
    init() { cache.totalCostLimit = 80 * 1024 * 1024; cache.countLimit = 100 }
    func cached(_ address: String?) -> NSImage? {
        guard let address, let url = URL(string: address), ArtworkPolicy.permits(url) else { return nil }
        return cache.object(forKey: url as NSURL)
    }
    func image(_ address: String?) async -> NSImage? {
        guard let address, let url = URL(string: address), ArtworkPolicy.permits(url) else { return nil }
        if let value = cache.object(forKey: url as NSURL) { return value }
        if let failed = failures[url], Date().timeIntervalSince(failed) < 15 { return nil }
        if let task = pending[url] { return await task.value }
        let task = Task {
            await gate.acquire()
            let result = try? await loader.load(url, maxPixelSize: 640)
            await gate.release()
            return result
        }; pending[url] = task
        let result = await task.value; pending[url] = nil
        failures = failures.filter { Date().timeIntervalSince($0.value) < 15 }
        if result == nil {
            if failures.count >= 100 { failures.removeAll(keepingCapacity: true) }
            failures[url] = Date()
        }
        if let result { failures[url] = nil; cache.setObject(result, forKey: url as NSURL, cost: Int(result.size.width * result.size.height) * 4) }
        return result
    }
}
/// A small shared queue prevents a large library from launching every thumbnail at once.
private actor ArtworkGate {
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func acquire() async {
        if running < 4 { running += 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() {
        if waiters.isEmpty { running -= 1 } else { waiters.removeFirst().resume() }
    }
}
