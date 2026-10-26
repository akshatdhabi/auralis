import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: PlayerSession!
    private var window: AuralisWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        model = PlayerSession()
        window = AuralisWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Auralis"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(Color.ink); window.minSize = NSSize(width: 900, height: 680)
        window.contentView = NSHostingView(rootView: WindowContent(model: model))
        window.delegate = self; window.setFrameAutosaveName("AuralisMainWindow")
        if !window.setFrameUsingName("AuralisMainWindow") { window.center() }
        window.collectionBehavior.insert(.fullScreenPrimary)
        model.window = window
        window.leaveImmersion = { [weak model] in
            guard let model, model.immersive else { return false }
            model.exitImmersive(); return true
        }
        makeMenu(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private func makeMenu() {
        let main = NSMenu()
        func menu(_ title: String) -> NSMenu { let item = NSMenuItem(); item.title = title; let menu = NSMenu(title: title); item.submenu = menu; main.addItem(item); return menu }
        func item(_ menu: NSMenu, _ title: String, _ selector: Selector, _ key: String = "") { let item = NSMenuItem(title: title, action: selector, keyEquivalent: key); item.target = self; menu.addItem(item) }
        let app = menu("Auralis")
        item(app, "About Auralis", #selector(about)); app.addItem(.separator())
        app.addItem(withTitle: "Hide Auralis", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(.separator()); app.addItem(withTitle: "Quit Auralis", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let edit = menu("Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key) }
        let music = menu("Music")
        item(music, "Play / Pause", #selector(toggle), "p"); item(music, "Next Track", #selector(nextTrack), "]"); item(music, "Previous Track", #selector(previousTrack), "[")
        music.addItem(.separator())
        item(music, "Start Radio for Current Track", #selector(startRadio), "r")
        music.items.last?.keyEquivalentModifierMask = [.command, .shift]
        music.addItem(.separator()); item(music, "Sign in with Google", #selector(signIn), "l"); item(music, "Reload YouTube Music", #selector(reload), "r")
        let view = menu("View")
        item(view, "Search Music", #selector(search), "k")
        item(view, "Browse", #selector(browse), "1"); item(view, "Now Playing", #selector(stage), "2"); item(view, "Toggle Full Screen", #selector(fullScreen), "f")
        view.items.last?.keyEquivalentModifierMask = [.control, .command]
        NSApp.mainMenu = main
    }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Auralis", .applicationVersion: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4") · Panorama preview", .credits: NSAttributedString(string: "Made for the music.\nUnofficial YouTube Music desktop client.\nAmbient visuals · quality controlled by YouTube Music.")])
    }
    @objc private func startRadio() { model.startRadio() }
    @objc private func toggle() { model.togglePlayback() }
    @objc private func nextTrack() { model.command(.nexttrack) }
    @objc private func previousTrack() { model.command(.previoustrack) }
    @objc private func signIn() { model.signIn() }
    @objc private func reload() { model.reload() }
    @objc private func browse() { if model.immersive { model.exitImmersive() }; model.stage = false; model.website = false }
    @objc private func search() { browse(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { NotificationCenter.default.post(name: .auralisSearch, object: nil) } }
    @objc private func stage() { model.stage = true }
    @objc private func fullScreen() { model.fullScreen() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { window.makeKeyAndOrderFront(nil); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { model.shutdown() }
}
private struct WindowContent: View {
    @Bindable var model: PlayerSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chromeClock = MotionClock()
    var body: some View {
        VStack(spacing: 0) {
            ChromePattern(accent: model.accent).frame(height: 24)
            PlayerView(model: model)
        }.background(Color.ink).coordinateSpace(name: "AuralisWindow")
            .environment(\.chromeClock, chromeClock)
            .onChange(of: model.active && !model.lowPower && !reduceMotion, initial: true) { _, running in chromeClock.setRunning(running) }
    }
}
/// Handle Escape at the window before the covered WebKit responder can consume it.
@MainActor final class AuralisWindow: NSWindow {
    var leaveImmersion: (() -> Bool)?
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, attachedSheet == nil,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
           leaveImmersion?() == true { return }
        super.sendEvent(event)
    }
}
@main enum AuralisMain {
    @MainActor static func main() {
        let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
