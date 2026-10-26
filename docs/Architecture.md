# Architecture

Auralis targets arm64 Macs on macOS 14 and later. It uses SwiftUI for the interface and AppKit for the window, scrolling and menu. There are no third-party runtime packages.

## Ownership and source boundaries

`AppDelegate` owns one `PlayerSession` and the main window. `PlayerSession` owns one persistent WKWebView for the app lifetime. Account/login sheets share `WKWebsiteDataStore.default()`. The development bundle identity is retained so upgrades preserve the existing website session; no cookie export or backup exists.

`EmbeddedPlayer` keeps the same source mounted behind an opaque native surface. Hit testing and accessibility are gated while covered. Native screens share one transport; the full website exposes only its first-party transport. An observed ad state returns to the website.

`PlayerAdapter.js` reads bounded public Media Session and HTML media facts and invokes normal playback controls. `BrowseAdapter.js` projects currently rendered first-party shelves, links and queue rows. Current-document WeakRef handles point back to the original controls. Detached controls, hidden cached pages and foreign links are rejected. Radio uses the original visible Start radio / Start mix action, with seed-title verification. There is no stream extraction, private catalog/playback API, ad skipping or bitrate override.

## Presentation

`BrowseView` and `ListeningView` contain native horizontal `PanoramaViewport` documents. Precise horizontal trackpad events retain native scrolling; vertical mouse-wheel input pans sideways. The queue remains a nested vertical list. Nearby panels instantiate their artwork/tasks; headings, covers and the background use different scroll offsets. The live viewport constrains cover/type sizes and reserves the credit/transport space when leaving full screen.

`ChromePattern` draws the drifting Jaali lattice in shared window coordinates and from a shared resumable clock, so the title bar, toolbar and page meet without an abrupt boundary. Explicit movement request/target inputs update the native scroll bridge when the rail is clicked. `MotionClock` freezes and resumes without jumping. Chrome motion stops during inactivity, Low Power Mode or Reduce Motion; listening-room motion also follows playback state. Canvas updates are isolated from controls. Live tiles reveal preloaded artwork inside a fixed card and retain anchored labels. No rotating metadata backs remain.

The compact current-track group is a separate accessible Now Playing button; playback and seek controls remain independent. Escape is handled at the window event boundary while immersive, unless a sheet is attached. System full-screen exit restores the regular presentation and prior queue visibility.

## Artwork

`ArtworkService` uses cookie/credential-free URLSession delegate chunks, exact-host redirect checks, image MIME validation and an 8 MB receive cap. Decode and accent extraction run away from the main actor. `BrowseArtworkCache` deduplicates requests, limits concurrency to four, downsamples thumbnails to 640 px and bounds memory to 80 MB / 100 images. Cached images render immediately when views return.

`ArtworkDiskCache` stores validated encoded images under hashed source-URL filenames in the user's Caches directory. Writes are atomic; entries expire after seven days and are pruned to 96 MB / 512 files. Corrupt images are evicted and fetched again. No session data is cached here. Visible thumbnails retry temporary failures at bounded 15-second intervals. The source adapter retains only public image URLs actually observed on a matching card during normal warm-up scrolling; a changed card identity invalidates that memory. Player covers can decode to 1600 px. A failed current-cover request may retry after 15 seconds; generation tokens prevent superseded requests from changing current artwork/loading state.

Initial rendered catalog content is published before provider thumbnail hydration finishes. Bounded normal scrolling warms the first shelf/queue and restores source offsets. A discarded 64-point WebKit render snapshot may wake covered lazy images. Neither mechanism captures audio or indexes unavailable provider content.

## Optional text

Track typography uses public metadata. `LyricsAdapter.js` reads the provider's existing rendered Lyrics tab, verifies the current title before/after the asynchronous operation and restores the previous tab. Lyrics remain in memory and are labeled unsynchronized.

`ArtistStoryService` performs an opt-in cookie-free Wikipedia lookup with exact-host redirects and a 256 KB response cap. It sends only the artist name. Matching rejects unrelated or ambiguous pages; at most twenty excerpts remain in memory. Source links/attribution stay visible. Stale text responses cannot replace a new track's context.

## Verification

`Scripts/check.sh` runs state/decoder checks, transport/cache fixtures, JavaScript fixtures, an optimized build with warnings treated as errors, strict signature verification and project/plist validation. GitHub Actions additionally runs hosted XCTest on an Apple Silicon macOS runner. See [validation](Validation.md) for observed results and remaining limits.
