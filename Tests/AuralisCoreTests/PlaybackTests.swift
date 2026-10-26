import XCTest
@testable import Auralis

final class PlaybackTests: XCTestCase {
    func snapshot(_ changes: [String: Any] = [:]) -> [String: Any] {
        var value: [String: Any] = ["title": "A title", "artist": "An artist", "album": "An album", "isPlaying": true,
            "position": 42.0, "duration": 180.0, "rate": 1.0, "actions": ["play", "pause", "seekto"], "adVisible": false]
        value.merge(changes) { _, new in new }; return value
    }
    func testHostBoundaries() {
        XCTAssertTrue(ProviderPolicy.isMusic(URL(string: "https://music.youtube.com/watch?v=x")))
        for url in ["https://music.youtube.com.evil.test", "http://music.youtube.com", "https://music.youtube.com:444", "https://x@y@music.youtube.com"] {
            XCTAssertFalse(ProviderPolicy.isMusic(URL(string: url)))
        }
        for url in ["https://i.ytimg.com.evil.test/a", "file:///etc/passwd", "https://user:secret@i.ytimg.com/a"] { XCTAssertFalse(ArtworkPolicy.permits(URL(string: url)!)) }
    }
    func testSAPISIDRequiresYouTubeScopeAndNotExpired() {
        func cookie(_ domain: String, _ expires: Date) -> HTTPCookie {
            HTTPCookie(properties: [.name: "SAPISID", .value: "synthetic-fixture", .domain: domain, .path: "/", .expires: expires])!
        }
        let now = Date()
        XCTAssertTrue(ProviderPolicy.hasSession([cookie(".youtube.com", now.addingTimeInterval(600))], now: now))
        XCTAssertFalse(ProviderPolicy.hasSession([cookie(".google.com", now.addingTimeInterval(600))], now: now))
        XCTAssertFalse(ProviderPolicy.hasSession([cookie(".youtube.com.evil.test", now.addingTimeInterval(600))], now: now))
        XCTAssertFalse(ProviderPolicy.hasSession([cookie(".youtube.com", now.addingTimeInterval(-600))], now: now))
    }
    func testRejectsInvalidSignals() {
        for changes: [String: Any] in [["position": -1], ["duration": 0], ["position": 182], ["rate": -1], ["actions": ["download"]], ["title": String(repeating: "a", count: 4097)]] {
            XCTAssertNil(PlaybackSnapshot.decode(snapshot(changes)))
        }
    }
    func testClockCannotRunAwayWhilePageIsUnresponsive() {
        let now = Date(), value = PlaybackSnapshot.decode(snapshot())!
        XCTAssertEqual(value.elapsed(received: now, now: now.addingTimeInterval(500)), 46)
        XCTAssertEqual(value.elapsed(received: now, now: now.addingTimeInterval(-5)), 42)
        let paused = PlaybackSnapshot.decode(snapshot(["isPlaying": false]))!
        XCTAssertEqual(paused.elapsed(received: now, now: now.addingTimeInterval(500)), 42)
    }
    func testMissingDurationRemainsUnknown() {
        let value = PlaybackSnapshot.decode(snapshot(["position": NSNull(), "duration": NSNull()]))!
        XCTAssertNil(value.elapsed(received: Date(), now: Date()))
        XCTAssertEqual(ClockText.format(nil), "—:——")
    }
    func testCatalogBoundsAndUnsupportedItems() {
        let item: [String: Any] = ["id": "document:1", "title": "A song", "subtitle": "An artist", "kind": "song"]
        func object(_ item: [String: Any], count: Int = 1) -> [String: Any] {
            ["path": "/", "heading": "", "library": [], "shelves": [["id": "one", "title": "Listen again", "items": Array(repeating: item, count: count)]]]
        }
        XCTAssertTrue(BrowseSnapshot.decode(object(item)) != nil)
        var route = object(item); route["route"] = String(repeating: "x", count: 4001)
        XCTAssertNil(BrowseSnapshot.decode(route))
        XCTAssertNil(BrowseSnapshot.decode(object(item, count: 25)))
        var bad = item; bad["kind"] = "download"; XCTAssertNil(BrowseSnapshot.decode(object(bad)))
        bad = item; bad["title"] = String(repeating: "x", count: 1001); XCTAssertNil(BrowseSnapshot.decode(object(bad)))
    }
    func testQueueAndRelatedLinkBounds() {
        let entry: [String: Any] = ["id": "queue:1", "title": "A queued track", "subtitle": "Artist", "current": true]
        let link: [String: Any] = ["id": "artist:1", "title": "Artist", "kind": "artist"]
        XCTAssertTrue(QueueSnapshot.decode(["items": [entry], "links": [link], "canRadio": true]) != nil)
        XCTAssertNil(QueueSnapshot.decode(["items": [entry, entry], "links": [], "canRadio": true]))
        XCTAssertNil(QueueSnapshot.decode(["items": Array(repeating: entry, count: 81), "links": [], "canRadio": true]))
        var bad = link; bad["kind"] = "download"
        XCTAssertNil(QueueSnapshot.decode(["items": [entry], "links": [bad], "canRadio": true]))
    }
    func testPanoramaBoundsAndPrefetchWindow() {
        XCTAssertEqual(PanoramaMath.clamp(-50, viewport: 1000, extent: 4000), 0)
        XCTAssertEqual(PanoramaMath.clamp(4500, viewport: 1000, extent: 4000), 3000)
        XCTAssertEqual(PanoramaMath.clamp(100, viewport: 1000, extent: 500), 0)
        XCTAssertTrue(PanoramaMath.nearby(origin: 1100, width: 800, offset: 0, viewport: 1000))
        XCTAssertFalse(PanoramaMath.nearby(origin: 2000, width: 800, offset: 0, viewport: 1000))
        XCTAssertFalse(PanoramaMath.nearby(origin: 0, width: 800, offset: 2000, viewport: 1000))
    }
    func testAtmosphereRejectsMismatchedOrUnsafeArtistSources() throws {
        func data(title: String = "Fixture Band", url: String = "https://en.wikipedia.org/wiki/Fixture_Band", disambiguation: Bool = false) throws -> Data {
            var page: [String: Any] = ["title": title, "fullurl": url, "extract": "Fixture Band is a synthetic music band used for testing artist name matching and source validation."]
            if disambiguation { page["pageprops"] = ["disambiguation": ""] }
            return try JSONSerialization.data(withJSONObject: ["query": ["pages": [page]]])
        }
        let valid = try data(), unrelated = try data(title: "Other Band"), ambiguous = try data(disambiguation: true)
        let foreign = try data(url: "https://en.wikipedia.org.evil.test/wiki/Fixture_Band")
        XCTAssertTrue(ArtistStory.decode(valid, artist: "Fixture Band") != nil)
        XCTAssertNil(ArtistStory.decode(unrelated, artist: "Fixture Band"))
        XCTAssertNil(ArtistStory.decode(ambiguous, artist: "Fixture Band"))
        XCTAssertNil(ArtistStory.decode(foreign, artist: "Fixture Band"))
        XCTAssertFalse(ArtistStory.permitsSource(URL(string: "https://secret@en.wikipedia.org/wiki/Fixture_Band")!))
        XCTAssertFalse(ArtistStory.permitsSource(URL(string: "http://en.wikipedia.org/wiki/Fixture_Band")!))
    }
    func testLyricsPayloadIsBounded() {
        XCTAssertTrue(LyricsSnapshot.decode(["title": "Synthetic track", "lines": ["A synthetic line"], "source": "YouTube Music"]) != nil)
        XCTAssertNil(LyricsSnapshot.decode(["title": "Synthetic track", "lines": Array(repeating: "line", count: 101), "source": "YouTube Music"]))
        XCTAssertNil(LyricsSnapshot.decode(["title": "Synthetic track", "lines": [String(repeating: "x", count: 1201)], "source": "YouTube Music"]))
    }
    func testDecorationClockFreezesAndResumesWithoutJumping() {
        let start = Date(timeIntervalSince1970: 1000)
        var clock = MotionClock()
        clock.setRunning(true, at: start)
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(3)), 3)
        clock.setRunning(false, at: start.addingTimeInterval(3))
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(100)), 3)
        clock.setRunning(true, at: start.addingTimeInterval(100))
        clock.setRunning(true, at: start.addingTimeInterval(101))
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(102)), 5)
        XCTAssertEqual(clock.elapsed(at: start.addingTimeInterval(-1)), 3)
    }
    func testFailedArtworkRetriesAndRejectsSupersededCompletion() {
        let now = Date(timeIntervalSince1970: 1000)
        var attempts = ArtworkAttempts()
        let first = attempts.begin(at: now)!
        XCTAssertNil(attempts.begin(at: now))
        XCTAssertTrue(attempts.finish(first, succeeded: false, at: now))
        XCTAssertNil(attempts.begin(at: now.addingTimeInterval(14)))
        let retry = attempts.begin(at: now.addingTimeInterval(15))!
        attempts.reset()
        let nextTrack = attempts.begin(at: now)!
        XCTAssertFalse(attempts.finish(retry, succeeded: true, at: now))
        XCTAssertTrue(attempts.isLoading)
        XCTAssertTrue(attempts.finish(nextTrack, succeeded: true, at: now))
        XCTAssertNil(attempts.begin(at: now.addingTimeInterval(500)))
    }

}
