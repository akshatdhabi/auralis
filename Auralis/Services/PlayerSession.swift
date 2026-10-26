import AppKit
import SwiftUI
import WebKit
import Observation

/// Owns one persistent player for the entire app lifetime. UI navigation never recreates it.
@Observable @MainActor final class PlayerSession: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    var snapshot: PlaybackSnapshot?
    var receivedAt = Date.distantPast
    var signedIn = false
    var loading = true
    var notice: String?
    var stage = false
    var artwork: NSImage?
    var artworkLoading = false
    var artworkAccent = Color.cyan
    var theme = 0
    var motion: AmbientMotion = .aurora
    var textAtmosphere: TextAtmosphere = .track
    var lyrics: LyricsSnapshot?
    var artistStory: ArtistStory?
    var contextBusy = false
    var contextMessage: String?
    var immersive = false
    private var immersionEnteredFullScreen = false
    private var immersionHadQueue = false
    private var contextGeneration = UUID()
    private var loadedContextKey = ""
    private let artistStories = ArtistStoryService()
    var contextKey: String { (snapshot?.title ?? "") + "|" + (snapshot?.artist ?? "") + "|" + (snapshot?.album ?? "") }

    var isFullScreen = false
    var fresh = false
    var commandPending = false
    var active = true
    var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var browse: BrowseSnapshot?
    var destination: BrowseDestination = .home
    var searchText = ""
    var browsingBusy = true
    var website = false
    var browseError: String?
    var queue: QueueSnapshot?
    var showQueue = true
    var queueBusy = false
    var radioBusy = false
    var loadingPage: String?
    private var adVisible = false
    var showingWebsite: Bool { (!stage && website) || adVisible }
    let store = WKWebsiteDataStore.default()
    private(set) var player: WKWebView!
    weak var window: NSWindow?
    private var sheet: NSWindow?
    private var auxiliary: WKWebView?
    private var sheetHost: NSTextField?
    private var loginMode = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var sampling = false
    private var artTask: Task<Void, Never>?
    private var artworkURL: String?
    private var artworkAttempts = ArtworkAttempts()
    private let artLoader = ArtworkService()
    private var systemMedia: SystemMediaController!
    private var adapter: String = ""
    private var browseAdapter = ""
    private var lastBrowseSample = Date.distantPast
    private var browseSampling = false
    private var warmedBrowseRoute: String?
    private var browseActionPending = false
    private var queueSampling = false
    private var lastQueueSample = Date.distantPast
    private var failures = 0
    private var recoveringProcess = false
    private var closing = false

    var accent: Color { [artworkAccent, Color.orange, Color.purple, Color.cyan][min(3, max(0, theme))] }
    var isPlaying: Bool { fresh && snapshot?.isPlaying == true }
    var title: String { snapshot?.title.isEmpty == false ? snapshot!.title : "Find your\nnext favourite." }
    var artist: String { snapshot?.artist ?? "Choose something in YouTube Music." }

    override init() {
        super.init()
        adapter = (Bundle.main.url(forResource: "PlayerAdapter", withExtension: "js").flatMap { try? String(contentsOf: $0) }) ?? "null"
        browseAdapter = (Bundle.main.url(forResource: "BrowseAdapter", withExtension: "js").flatMap { try? String(contentsOf: $0) }) ?? "null"
        player = makeWebView()
        systemMedia = SystemMediaController(model: self)
        store.httpCookieStore.add(self)
        observeLifecycle()
        Task { await refreshAuth() }
        player.load(URLRequest(url: ProviderPolicy.musicURL))
        startTimer()
    }
    private func makeWebView() -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.preferences.isElementFullscreenEnabled = true
        let web = PlayerWebView(frame: .zero, configuration: config)
        let safari = Bundle(path: "/Applications/Safari.app")?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "26.4"
        web.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safari) Safari/605.1.15"
        web.navigationDelegate = self; web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.underPageBackgroundColor = NSColor(red: 0.035, green: 0.03, blue: 0.045, alpha: 1)
        return web
    }
    private func observeLifecycle() {
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                Task { @MainActor in
                    guard let self else { return }
                    self.active = notification.name == NSApplication.didBecomeActiveNotification
                    self.startTimer(); await self.poll()
                }
            })
        }
        observers.append(center.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.timer?.invalidate(); self?.fresh = false; self?.systemMedia.clear() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.startTimer(); await self?.refreshAuth(); await self?.poll() }
        })
    }
    private func startTimer() {
        timer?.invalidate()
        guard !closing else { return }
        timer = Timer.scheduledTimer(withTimeInterval: active ? 0.75 : 2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }
    func supports(_ action: PlaybackAction) -> Bool {
        fresh && !commandPending && snapshot?.actions.contains(action.rawValue) == true
    }
    func position(at date: Date) -> Double? {
        guard let snapshot else { return nil }
        return fresh ? snapshot.elapsed(received: receivedAt, now: date) : snapshot.position
    }
    private func script(_ request: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: request), let json = String(data: data, encoding: .utf8) else { return "null" }
        return adapter.replacingOccurrences(of: "__REQUEST__", with: json)
    }
    func poll() async {
        if Date().timeIntervalSince(receivedAt) > 6 { fresh = false; systemMedia.clear() }
        guard !sampling, !closing, ProviderPolicy.isMusic(player.url) else { return }
        sampling = true; defer { sampling = false }
        do {
            let object = try await player.evaluateJavaScript(script([:]))
            guard let object, let fact = PlaybackSnapshot.decode(object) else { return }
            if snapshot != fact { snapshot = fact }; receivedAt = Date(); if !fresh { fresh = true }; failures = 0
            if adVisible != fact.adVisible { adVisible = fact.adVisible }
            updateArtwork(fact.artwork)
            systemMedia.update(snapshot: fact, position: fact.position, artwork: artwork)
            if active && !stage && !showingWebsite && !browseActionPending && Date().timeIntervalSince(lastBrowseSample) > 5 { await refreshBrowse() }
            if active && (stage || queue == nil) && Date().timeIntervalSince(lastQueueSample) > 3 { await refreshQueue() }
        } catch {
            failures += 1
            if failures >= 3 { fresh = false; systemMedia.clear(); notice = "Music is taking a moment. Browse is still available." }
        }
    }
    func command(_ action: PlaybackAction, seekTime: Double? = nil) {
        guard supports(action), ProviderPolicy.isMusic(player.url) else { return }
        commandPending = true
        Task {
            defer { commandPending = false }
            var request: [String: Any] = ["action": action.rawValue]
            if let seekTime, seekTime.isFinite { request["position"] = seekTime }
            do {
                let result = try await player.callAsyncJavaScript("return await (" + script(request) + ");", arguments: [:], in: nil, contentWorld: .page)
                let accepted = result as? Bool ?? false
                notice = accepted ? nil : "Start this track in YouTube Music, then return to Auralis."
                if !accepted { openWebsite() }
            } catch { notice = "That control is unavailable. Try it in YouTube Music." }
            await poll()
        }
    }
    func togglePlayback() { command(isPlaying ? .pause : .play) }
    private func browseScript(_ request: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: request), let json = String(data: data, encoding: .utf8) else { return "null" }
        return browseAdapter.replacingOccurrences(of: "__REQUEST__", with: json)
    }
    func prepareBrowse() async {
        guard !stage, !website, !browseActionPending, ProviderPolicy.isMusic(player.url) else { return }
        browsingBusy = true
        let closed = try? await player.callAsyncJavaScript("return (" + browseScript(["action": "close-queue"]) + ");", arguments: [:], in: nil, contentWorld: .page)
        if closed as? Bool == true { try? await Task.sleep(for: .milliseconds(250)) }
        await refreshBrowse()
    }
    func refreshBrowse() async {
        guard !browseSampling, !closing, ProviderPolicy.isMusic(player.url) else { return }
        browseSampling = true; defer { browseSampling = false }
        lastBrowseSample = Date()
        do {
            guard let object = try await player.evaluateJavaScript(browseScript([:])), var value = BrowseSnapshot.decode(object) else { return }
            // Publish available cards now; normal provider scrolling may hydrate more images below.
            if browse != value { browse = value }
            let route = value.route ?? value.path
            if !stage, !showingWebsite, warmedBrowseRoute != route, !value.shelves.isEmpty {
                warmedBrowseRoute = route
                // A public WebKit snapshot requests a render of the covered viewport. The tiny
                // result is discarded; it is never saved or used as catalog/account data.
                if value.shelves.flatMap(\.items).allSatisfy({ $0.artwork == nil }) {
                    let configuration = WKSnapshotConfiguration(); configuration.snapshotWidth = 64
                    _ = try? await player.takeSnapshot(configuration: configuration)
                }
                // Normal bounded scrolling hydrates the provider's first shelf, then restores
                // its offsets. Artwork changes use these real rendered sources only.
                _ = try? await player.callAsyncJavaScript("return await (" + browseScript(["action": "warm-browse"]) + ");", arguments: [:], in: nil, contentWorld: .page)
                if let refreshed = try? await player.evaluateJavaScript(browseScript([:])), let rendered = BrowseSnapshot.decode(refreshed) { value = rendered }
            }
            if browse != value { browse = value }
            if value.path == "/" { destination = .home }
            else if value.path == "/explore" { destination = .explore }
            else if value.path == "/library" || value.path.hasPrefix("/library/") { destination = .library }
            if !browseActionPending { browsingBusy = false; browseError = nil }
        } catch { if !browseActionPending { browsingBusy = false; browseError = "The music page is taking a moment." } }
    }
    private func browseAction(_ request: [String: Any], title: String? = nil, preserveStage: Bool = false) {
        guard !browseActionPending, ProviderPolicy.isMusic(player.url) else { return }
        if !preserveStage { stage = false }
        website = false; browseActionPending = true; browsingBusy = true; browseError = nil
        loadingPage = title
        let previous = browse
        let previousResponder = window?.firstResponder
        let needsProviderFocus = request["action"] as? String == "radio"
        radioBusy = needsProviderFocus
        if needsProviderFocus {
            NSApp.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
            window?.makeFirstResponder(player)
        }
        Task {
            defer {
                browseActionPending = false; browsingBusy = false; loadingPage = nil; radioBusy = false
                if needsProviderFocus { window?.makeFirstResponder(previousResponder) }
            }
            do {
                let result = try await player.callAsyncJavaScript("return await (" + browseScript(request) + ");", arguments: [:], in: nil, contentWorld: .page)
                if result as? Bool != true {
                    if request["action"] as? String == "radio" { notice = "Radio couldn’t be started here. Try the item’s menu in YouTube Music." }
                    else { browseError = "Open this page in YouTube Music to continue." }
                    return
                }
                // Keep the loading surface visible until a new rendered page has content.
                // The provider is asynchronous; a fixed delay can incorrectly show its old page as ready.
                if let pageTitle = title {
                    for _ in 0..<24 {
                        try await Task.sleep(for: .milliseconds(250))
                        await refreshBrowse()
                        if let value = browse, !value.shelves.isEmpty,
                           value.route != previous?.route || value.path != previous?.path || value.heading != previous?.heading || value.heading.localizedCaseInsensitiveCompare(pageTitle) == .orderedSame { break }
                    }
                    if browse?.route == previous?.route && browse?.heading == previous?.heading && browse?.heading.localizedCaseInsensitiveCompare(pageTitle) != .orderedSame { browseError = "This page hasn’t opened yet. Try again or use the full YouTube Music view." }
                } else {
                    try await Task.sleep(for: .milliseconds(300)); await refreshBrowse()
                }
                if request["action"] as? String == "radio" {
                    await warmQueueArtwork()
                }
                await refreshQueue()
                if request["action"] as? String == "radio" {
                    await poll()
                    if !isPlaying && supports(.play) { command(.play) }
                }
            } catch { browseError = "This action is unavailable. Try it in YouTube Music." }
        }
    }
    func select(_ item: BrowseItem) { browseAction(["action": "select", "id": item.id], title: item.kind == "song" ? nil : item.title) }
    func open(_ link: BrowseLink) { browseAction(["action": "select", "id": link.id], title: ["play", "shuffle"].contains(link.kind) ? nil : link.title) }
    func playQueue(_ item: QueueEntry) { browseAction(["action": "select", "id": item.id], preserveStage: true) }
    func startRadio(_ item: BrowseItem? = nil) {
        var request: [String: Any] = ["action": "radio"]
        if let item { request["id"] = item.id; request["title"] = item.title }
        browseAction(request, preserveStage: true)
    }
    func refreshQueue() async {
        guard !queueSampling, !closing, ProviderPolicy.isMusic(player.url) else { return }
        queueSampling = true; defer { queueSampling = false }
        lastQueueSample = Date()
        if let object = try? await player.evaluateJavaScript(browseScript(["action": "queue"])), let value = QueueSnapshot.decode(object) {
            if queue != value { queue = value }
        }
    }
    func toggleQueue() {
        showQueue.toggle()
        if showQueue { loadQueue() }
    }
    private func warmQueueArtwork() async {
        guard stage && showQueue else { return }
        _ = try? await player.callAsyncJavaScript("return await (" + browseScript(["action": "warm-queue"]) + ");", arguments: [:], in: nil, contentWorld: .page)
    }
    func loadQueue() {
        queueBusy = true
        Task {
            defer { queueBusy = false }
            _ = try? await player.callAsyncJavaScript("return (" + browseScript(["action": "open-queue"]) + ");", arguments: [:], in: nil, contentWorld: .page)
            try? await Task.sleep(for: .milliseconds(400))
            await warmQueueArtwork()
            await refreshQueue()
        }
    }
    func fullQueue() { loadQueue(); openWebsite() }
    func navigate(_ destination: BrowseDestination) {
        self.destination = destination; searchText = ""
        browseAction(["action": "navigate", "destination": destination.rawValue], title: destination == .home ? "for you" : destination == .explore ? "discover" : "your library")
    }
    func search() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 240 else { return }
        browseAction(["action": "search", "query": query], title: "search")
    }
    func browseBack() { browseAction(["action": "back"], title: "your music") }
    func openWebsite() { website = true; stage = false }
    func reload() { notice = nil; fresh = false; systemMedia.clear(); player.load(URLRequest(url: ProviderPolicy.musicURL)) }
    func enterImmersive() {
        guard !immersive else { return }
        immersionHadQueue = showQueue
        stage = true; website = false; showQueue = false; immersive = true
        immersionEnteredFullScreen = !isFullScreen
        if immersionEnteredFullScreen { fullScreen() }
    }
    func exitImmersive() {
        immersive = false; showQueue = immersionHadQueue
        if immersionEnteredFullScreen && isFullScreen { fullScreen() }
        immersionEnteredFullScreen = false
    }
    func openStorySource() {
        guard let url = artistStory?.url, ArtistStory.permitsSource(url) else { return }
        showSheet(url: url, login: false)
    }
    func prepareTextAtmosphere() async {
        guard stage, fresh, let snapshot, !snapshot.title.isEmpty else { return }
        let key = contextKey, generation = UUID(), mode = textAtmosphere
        contextGeneration = generation
        if loadedContextKey != key { lyrics = nil; artistStory = nil; loadedContextKey = key }
        contextMessage = nil; contextBusy = false
        guard mode == .artist || mode == .lyrics else { return }
        if mode == .artist && artistStory?.artist == snapshot.artist { return }
        if mode == .lyrics && lyrics?.title == snapshot.title { return }
        contextBusy = true
        defer { if contextGeneration == generation { contextBusy = false } }
        do {
            if mode == .artist {
                let story = try await artistStories.story(for: snapshot.artist)
                guard !Task.isCancelled, contextGeneration == generation, contextKey == key else { return }
                artistStory = story
                if story == nil { contextMessage = "Artist story unavailable. Showing track typography." }
            } else {
                guard !browseActionPending, ProviderPolicy.isMusic(player.url),
                      let scriptURL = Bundle.main.url(forResource: "LyricsAdapter", withExtension: "js"),
                      let titleData = try? JSONSerialization.data(withJSONObject: [snapshot.title]),
                      let titleJSON = String(data: titleData, encoding: .utf8) else { return }
                _ = try? await player.callAsyncJavaScript("return (" + browseScript(["action": "open-queue"]) + ");", arguments: [:], in: nil, contentWorld: .page)
                try await Task.sleep(for: .milliseconds(300))
                let escapedTitle = String(titleJSON.dropFirst().dropLast())
                let script = try String(contentsOf: scriptURL).replacingOccurrences(of: "__TITLE__", with: escapedTitle)
                let object = try await player.callAsyncJavaScript("return await (" + script + ");", arguments: [:], in: nil, contentWorld: .page)
                guard !Task.isCancelled, contextGeneration == generation, contextKey == key else { return }
                if let object, let value = LyricsSnapshot.decode(object), value.title == snapshot.title { lyrics = value }
                if lyrics == nil { contextMessage = "Lyrics aren’t available from this page. Showing track typography." }
            }
        } catch {
            if !Task.isCancelled, contextGeneration == generation, contextKey == key {
                contextMessage = mode == .artist ? "Artist story couldn’t load. Showing track typography." : "Lyrics couldn’t load. Showing track typography."
            }
        }
    }
    func fullScreen() { window?.toggleFullScreen(nil) }
    private func updateArtwork(_ address: String?) {
        if address != artworkURL {
            artworkURL = address; artTask?.cancel(); artworkAttempts.reset()
            artwork = BrowseArtworkCache.shared.cached(address); artworkLoading = false
        }
        guard let address, let url = URL(string: address), ArtworkPolicy.permits(url),
              let attempt = artworkAttempts.begin() else { return }
        artworkLoading = artwork == nil
        artTask = Task {
            var succeeded = false
            defer { if artworkAttempts.finish(attempt, succeeded: succeeded) { artworkLoading = false } }
            guard let image = try? await artLoader.load(url), !Task.isCancelled, artworkAttempts.generation == attempt else { return }
            artwork = image
            succeeded = true
            let color = await Task.detached(priority: .utility) { ArtworkService.accent(from: image) }.value
            guard !Task.isCancelled, artworkAttempts.generation == attempt else { return }
            if let color { artworkAccent = Color(nsColor: color) }
            if let snapshot, fresh { systemMedia.update(snapshot: snapshot, position: position(at: Date()), artwork: image) }
        }
    }
    func refreshAuth() async {
        let cookies = await store.httpCookieStore.allCookies()
        let wasSignedIn = signedIn
        signedIn = ProviderPolicy.hasSession(cookies)
        if loginMode, signedIn, ProviderPolicy.isMusic(auxiliary?.url) { closeSheet(); reload() }
        else if wasSignedIn && !signedIn { reload() }
    }
    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) { Task { await refreshAuth() } }
    func signIn() { showSheet(url: ProviderPolicy.loginURL, login: true) }
    func account() {
        if signedIn { showSheet(url: URL(string: "https://www.youtube.com/account")!, login: false) }
        else { signIn() }
    }
    private func showSheet(url: URL, login: Bool) {
        guard let window else { return }
        if sheet != nil { return }
        let web = makeWebView(); auxiliary = web; loginMode = login
        precondition(web.configuration.websiteDataStore === player.configuration.websiteDataStore)
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 720), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        panel.title = login ? "Sign in with Google" : (url.host ?? "Account")
        let close = NSButton(title: "Done", target: self, action: #selector(closeSheet))
        let back = NSButton(title: "Back", target: self, action: #selector(sheetBack))
        let label = NSTextField(labelWithString: login ? "accounts.google.com · Your sign-in stays in this app." : (url.host ?? ""))
        sheetHost = label
        label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor
        let top = NSStackView(views: [back, label, close]); top.spacing = 14
        let container = NSView(); panel.contentView = container
        for v in [top, web] { v.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(v) }
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14), top.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            top.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            web.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 10), web.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: container.trailingAnchor), web.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        sheet = panel; window.beginSheet(panel); web.load(URLRequest(url: url))
    }
    @objc private func sheetBack() { auxiliary?.goBack() }
    @objc func closeSheet() {
        guard let panel = sheet else { return }
        window?.endSheet(panel); panel.orderOut(nil); auxiliary = nil; sheet = nil; sheetHost = nil; loginMode = false
        Task { await refreshAuth(); await poll() }
    }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        if webView === player { loading = true; warmedBrowseRoute = nil; fresh = false; systemMedia.clear() }
        else { sheetHost?.stringValue = webView.url?.host ?? "Loading…" }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if webView === player { loading = false; notice = nil; recoveringProcess = false; Task { await poll(); await refreshBrowse() } }
        else { sheetHost?.stringValue = webView.url?.host ?? "" }
        Task { await refreshAuth() }
    }
    private func navigationFailed(_ web: WKWebView, error: Error) {
        guard web === player, (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false; fresh = false; systemMedia.clear()
        notice = "YouTube Music couldn’t load. Check your connection, then try Reload."
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { navigationFailed(webView, error: error) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { navigationFailed(webView, error: error) }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        guard ProviderPolicy.isHTTPS(url) else { decisionHandler(.cancel); return }
        // Frame resources stay under WebKit's origin rules. Only top-level navigation is routed.
        if navigationAction.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        if webView === player && !ProviderPolicy.isMusic(url) {
            decisionHandler(.cancel)
            showSheet(url: url.host == "accounts.google.com" ? ProviderPolicy.loginURL : url, login: url.host == "accounts.google.com")
        } else { decisionHandler(.allow) }
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url, ProviderPolicy.isHTTPS(url) else { return nil }
        if webView === auxiliary { webView.load(navigationAction.request) }
        else if ProviderPolicy.isMusic(url) { player.load(navigationAction.request) }
        else { showSheet(url: url, login: url.host == "accounts.google.com") }
        return nil
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) { decisionHandler(.deny) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === player else { return }
        fresh = false; systemMedia.clear()
        if !recoveringProcess { recoveringProcess = true; player.reload(); notice = "Restoring YouTube Music…" }
        else { loading = false; notice = "YouTube Music stopped responding. Choose Reload to try again." }
    }
    func shutdown() {
        closing = true; timer?.invalidate(); artTask?.cancel(); store.httpCookieStore.remove(self); systemMedia.shutdown()
        for token in observers { NotificationCenter.default.removeObserver(token); NSWorkspace.shared.notificationCenter.removeObserver(token) }
        observers.removeAll()
    }
}
