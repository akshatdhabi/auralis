import AppKit
import Foundation
import ImageIO

/// Cookie-free, chunked thumbnail downloads with an 8 MB cap before decoding.
/// URLSession delivers Data chunks instead of millions of asynchronous single-byte operations.
final class ArtworkService: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private struct Transfer {
        let continuation: CheckedContinuation<Data, Error>
        var data = Data()
    }
    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]
    private var session: URLSession!
    private let diskCache: ArtworkDiskCache?
    override convenience init() { self.init(configuration: .ephemeral, diskCache: .shared) }
    init(configuration config: URLSessionConfiguration, diskCache: ArtworkDiskCache? = nil) {
        self.diskCache = diskCache
        super.init()
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(ArtworkPolicy.permits) == true ? request : nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.url.map(ArtworkPolicy.permits) == true, http.mimeType?.hasPrefix("image/") == true,
              http.expectedContentLength <= 8_000_000 else {
            finish(dataTask.taskIdentifier, error: URLError(.badServerResponse)); completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard let count = transfers[dataTask.taskIdentifier]?.data.count else { lock.unlock(); return }
        if count + data.count > 8_000_000 {
            lock.unlock(); finish(dataTask.taskIdentifier, error: URLError(.dataLengthExceedsMaximum)); dataTask.cancel(); return
        }
        transfers[dataTask.taskIdentifier]?.data.append(data); lock.unlock()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { finish(task.taskIdentifier, error: error) }
    private func finish(_ id: Int, error: Error?) {
        lock.lock(); let transfer = transfers.removeValue(forKey: id); lock.unlock()
        guard let transfer else { return }
        if let error { transfer.continuation.resume(throwing: error) }
        else { transfer.continuation.resume(returning: transfer.data) }
    }
    private func register(_ continuation: CheckedContinuation<Data, Error>, task: URLSessionDataTask) {
        lock.lock(); transfers[task.taskIdentifier] = Transfer(continuation: continuation); lock.unlock()
    }
    func load(_ url: URL, maxPixelSize: Int = 1600) async throws -> NSImage {
        guard ArtworkPolicy.permits(url) else { throw URLError(.unsupportedURL) }
        try Task.checkCancellation()
        if let data = await diskCache?.data(for: url) {
            do {
                let image = try await decode(data, maxPixelSize: maxPixelSize)
                try Task.checkCancellation(); return image
            } catch {
                try Task.checkCancellation()
                await diskCache?.remove(url)
            }
        }
        let data = try await download(url)
        let image = try await decode(data, maxPixelSize: maxPixelSize)
        try Task.checkCancellation()
        // Persist only after MIME, byte limits and actual image decoding succeed.
        await diskCache?.store(data, for: url)
        return image
    }
    private func download(_ url: URL) async throws -> Data {
        let ticket = ArtworkTicket()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: url)
                register(continuation, task: task); ticket.start(task)
            }
        } onCancel: { ticket.cancel() }
    }
    private func decode(_ data: Data, maxPixelSize: Int) async throws -> NSImage {
        // Decode at a bounded display size away from the main actor.
        return try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }.value
    }
    static func accent(from image: NSImage) -> NSColor? {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        var best: NSColor?; var bestScore: CGFloat = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: max(1, bitmap.pixelsHigh / 12)) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: max(1, bitmap.pixelsWide / 12)) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                let score = s * (1 - abs(b - 0.72))
                if score > bestScore && a > 0.5 {
                    bestScore = score
                    best = NSColor(hue: h, saturation: min(0.82, max(0.45, s)), brightness: 0.95, alpha: 1)
                }
            }
        }
        return best
    }
}

private final class ArtworkTicket: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var cancelled = false
    func start(_ task: URLSessionTask) {
        lock.lock(); self.task = task; let cancel = cancelled; lock.unlock()
        task.resume(); if cancel { task.cancel() }
    }
    func cancel() { lock.lock(); cancelled = true; let task = task; lock.unlock(); task?.cancel() }
}
