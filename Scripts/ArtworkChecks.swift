import AppKit
import Foundation

/// Deterministic transport fixtures: no network, cookies, or account data.
private final class ThumbnailProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var counts: [URL: Int] = [:]
    static func count(_ url: URL) -> Int { lock.lock(); defer { lock.unlock() }; return counts[url, default: 0] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.counts[request.url!, default: 0] += 1; Self.lock.unlock()
        let mode = request.url!.lastPathComponent
        if mode == "cancel" { return } // Cancellation must resume the suspended caller.
        let mime = mode == "mime" ? "text/html" : "image/png"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if mode == "large" {
            let chunk = Data(repeating: 0, count: 1_000_000)
            for _ in 0..<9 { client?.urlProtocol(self, didLoad: chunk) }
        } else {
            let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!
            for offset in stride(from: 0, to: png.count, by: 16) {
                client?.urlProtocol(self, didLoad: png.subdata(in: offset..<min(offset + 16, png.count)))
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main enum ArtworkChecks {
    @MainActor static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ThumbnailProtocol.self]
        let service = ArtworkService(configuration: config)
        let start = Date()
        let image = try await service.load(URL(string: "https://i.ytimg.com/valid")!, maxPixelSize: 640)
        precondition(image.size.width == 1 && image.size.height == 1)
        let palette = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32)!
        palette.setColor(NSColor(deviceRed: 0, green: 1, blue: 0, alpha: 1), atX: 0, y: 0)
        let green = NSImage(size: NSSize(width: 1, height: 1)); green.addRepresentation(palette)
        let accent = ArtworkService.accent(from: green)!
        precondition(abs(accent.hueComponent - 1.0 / 3) < 0.01 && accent.saturationComponent > 0.8)
        for mode in ["large", "mime"] {
            do {
                _ = try await service.load(URL(string: "https://i.ytimg.com/\(mode)")!)
                fatalError("Invalid artwork accepted: \(mode)")
            } catch { /* expected rejection */ }
        }
        let pending = Task { _ = try await service.load(URL(string: "https://i.ytimg.com/cancel")!) }
        try await Task.sleep(for: .milliseconds(30)); pending.cancel()
        do { _ = try await pending.value; fatalError("Cancelled artwork accepted") } catch {}
        do { _ = try await service.load(URL(string: "https://example.com/no")!); fatalError("Foreign host accepted") } catch {}
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("auralis-artwork-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = URL(string: "https://i.ytimg.com/persistent")!
        let disk = ArtworkDiskCache(directory: directory)
        func configuration() -> URLSessionConfiguration {
            let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [ThumbnailProtocol.self]; return config
        }
        _ = try await ArtworkService(configuration: configuration(), diskCache: disk).load(url)
        // Fresh loader and cache instance model relaunch: no second transport request.
        let relaunched = ArtworkDiskCache(directory: directory)
        _ = try await ArtworkService(configuration: configuration(), diskCache: relaunched).load(url)
        precondition(ThumbnailProtocol.count(url) == 1, "Relaunch cache downloaded again")
        // A corrupt cached body must recover from the source, not poison subsequent views.
        await relaunched.store(Data("invalid image".utf8), for: url)
        _ = try await ArtworkService(configuration: configuration(), diskCache: relaunched).load(url)
        precondition(ThumbnailProtocol.count(url) == 2)
        let expired = await relaunched.data(for: url, now: Date().addingTimeInterval(8 * 24 * 60 * 60))
        precondition(expired == nil, "Expired image returned")
        let tinyDirectory = directory.appendingPathComponent("budget")
        let tiny = ArtworkDiskCache(directory: tinyDirectory, byteLimit: 100)
        await tiny.store(Data(repeating: 1, count: 60), for: url)
        await tiny.store(Data(repeating: 2, count: 60), for: URL(string: "https://i.ytimg.com/other")!)
        let files = try FileManager.default.contentsOfDirectory(at: tinyDirectory, includingPropertiesForKeys: [.fileSizeKey])
        let bytes = try files.reduce(0) { try $0 + $1.resourceValues(forKeys: [.fileSizeKey]).fileSize! }
        precondition(bytes <= 100)
        let unsafe = URL(string: "https://example.com/no")!
        await tiny.store(Data([1]), for: unsafe)
        let rejected = await tiny.data(for: unsafe); precondition(rejected == nil)
        let countDirectory = directory.appendingPathComponent("count")
        let counted = ArtworkDiskCache(directory: countDirectory, byteLimit: 10000, countLimit: 1)
        await counted.store(Data([1]), for: url)
        await counted.store(Data([2]), for: URL(string: "https://i.ytimg.com/second")!)
        let kept = try FileManager.default.contentsOfDirectory(atPath: countDirectory.path)
        precondition(kept.count == 1, "Tiny images bypassed file-count budget")
        print("PASS · thumbnail transport, relaunch cache without redownload, corrupt-cache recovery, expiry, byte budget, cancellation and host policy (\(Int(Date().timeIntervalSince(start) * 1000)) ms, local fixtures)")
    }
}
