# Validation · 0.5.1 (build 16)

## Local automated checks

- Twelve same-source core test methods cover exact origins/cookie scope, invalid and bounded payloads, timing, queue/catalog limits, atmosphere sources, panorama bounds, a pause/resume clock, failed-artwork retry and superseded completion rejection.
- Artwork fixtures cover chunked decoding, MIME/8 MB limits, cancellation, exact hosts, persistence across fresh loader/cache instances without redownload, corrupt-cache recovery, expiry, and byte/file-count budgets.
- Playback, browse/radio/queue/search and rendered-lyrics fixtures cover public controls, rejected actions, hidden/detached content and origin/source matching.
- Optimized arm64/macOS 14 compilation treats warnings as errors. The build verifies its strict ad-hoc signature. Project/plist and script syntax are checked.

All local checks passed for this revision. [GitHub Actions run 40441761678](https://github.com/akshatdhabi/auralis/actions/runs/40441761678) passed on macOS 15 for commit `232011a`: the complete check script, optimized arm64 build, and Xcode hosted XCTest (12 tests, zero failures). SDK compatibility fixes confine AppKit images to the main actor, transfer only immutable decoded pixels, and capture scalar geometry in scroll transitions. Local fixture timings are not live network or frame-rate benchmarks.

## Previous live checks retained

In-app sign-in and normal relaunch persistence were observed. Native Browse, artist/album/playlist navigation, search, playback/seek, source queue selection and radio were checked against the provider. The bottom-bar song area opens Now Playing without issuing a playback command. In the current pass, panorama rail actions moved immediately and the left control became enabled; the representable now receives explicit movement inputs. The title bar, toolbar and page were visually checked with a shared-coordinate pattern, removing the reported cutoff. Lyrics availability was observed, with explicit unsynchronized labeling. The optional Wikipedia service resolved a matching music artist; its native menu path has not been comprehensively verified.

Full-screen round trips through the visible Exit control, system toggle and Escape restored the native header, queue, credit, rail and transport. Artwork-first tiles were inspected after replacing the rejected metadata backs.

## Limits

This is an ad-hoc signed development preview. Developer ID/notarization, physical media keys and displayed OS Now Playing, VoiceOver, localization, measured energy/FPS, sleep/wake/network recovery, every window/scale combination and the wider OS/M-series runtime matrix are not certified here. The deployment target and architecture do not establish testing on every model. Optional provider content can be unavailable. All ambient motion uses time and observed playback state, never decoded audio.

The README GIFs were captured from the running app, resized and looped; no frame-rate guarantee is inferred. The navigation demo holds each screen and uses an edited dissolve. Its 14 decoded frames were checked against the intended full frames to catch palette/disposal artifacts; it loops over 4.92 seconds. New automated cases verify that an observed public thumbnail URL survives source virtualization only while the card identity still matches.

The public repository excludes account/session data, image caches, personal screenshots, old companion prototypes, test binaries and historical setup records.
