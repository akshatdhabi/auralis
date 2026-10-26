import SwiftUI
import WebKit

struct EmbeddedPlayer: NSViewRepresentable {
    let session: PlayerSession
    func makeNSView(context: Context) -> WKWebView {
        (session.player as? PlayerWebView)?.acceptsSurfaceInput = session.showingWebsite
        return session.player
    }
    func updateNSView(_ nsView: WKWebView, context: Context) { (nsView as? PlayerWebView)?.acceptsSurfaceInput = session.showingWebsite }
}
/// NSViewRepresentable needs a native hit-test gate as well as SwiftUI's allowsHitTesting.
final class PlayerWebView: WKWebView {
    var acceptsSurfaceInput = true
    override func hitTest(_ point: NSPoint) -> NSView? { acceptsSurfaceInput ? super.hitTest(point) : nil }
}
