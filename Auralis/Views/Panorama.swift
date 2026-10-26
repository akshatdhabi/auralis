import SwiftUI
import AppKit
import QuartzCore
import Observation

/// Shared rhythm, adapted from the supplied Jaali reference. The user's stronger
/// type direction takes precedence over the reference's very thin headings.
enum MusicMotion {
    static let settle = Animation.timingCurve(0.1, 0.9, 0.2, 1, duration: 0.62)
}

@Observable @MainActor final class PanoramaPosition {
    var offset: CGFloat = 0
    var viewport: CGFloat = 1
    var extent: CGFloat = 1
    var target: CGFloat = 0
    var request = 0
    var reduceMotion = false
    var progress: CGFloat { extent > viewport ? min(1, max(0, offset / (extent - viewport))) : 0 }
    func move(to value: CGFloat) { target = PanoramaMath.clamp(value, viewport: viewport, extent: extent); request += 1 }
    func advance(_ direction: CGFloat) { move(to: offset + direction * viewport * 0.78) }
}

private struct PanoramaOriginKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var panoramaOrigin: CGFloat {
        get { self[PanoramaOriginKey.self] }
        set { self[PanoramaOriginKey.self] = newValue }
    }
}

/// A real AppKit horizontal document: precise trackpad momentum stays native.
/// A vertical mouse wheel pans across the landscape; nested song lists retain
/// their own native vertical scrolling. No timer or spring chases scroll input.
struct PanoramaViewport<Content: View>: NSViewRepresentable {
    let position: PanoramaPosition
    let size: CGSize
    let contentWidth: CGFloat
    let resetKey: String
    let moveRequest: Int
    let requestedOffset: CGFloat
    @ViewBuilder var content: () -> Content
    func makeCoordinator() -> Coordinator { Coordinator(position) }
    func makeNSView(context: Context) -> MusicPanoramaScrollView {
        let scroll = MusicPanoramaScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder; scroll.automaticallyAdjustsContentInsets = false; scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scroll.hasHorizontalScroller = false; scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .allowed; scroll.verticalScrollElasticity = .none
        scroll.autohidesScrollers = true
        let host = NSHostingView(rootView: AnyView(content().environment(position)))
        host.sizingOptions = []
        scroll.documentView = host
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.host = host
        context.coordinator.token = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak scroll, weak coordinator = context.coordinator] _ in
            guard let scroll, let coordinator else { return }
            MainActor.assumeIsolated {
                let offset = scroll.contentView.bounds.origin.x
                if coordinator.updating { DispatchQueue.main.async { coordinator.position.offset = offset } }
                else { coordinator.position.offset = offset }
            }
        }
        updateNSView(scroll, context: context)
        return scroll
    }
    func updateNSView(_ scroll: MusicPanoramaScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.updating = true; defer { coordinator.updating = false }
        // Type erasure keeps the native document identity stable across data updates.
        if let host = coordinator.host as? NSHostingView<AnyView> {
            host.rootView = AnyView(content().environment(position))
        }
        let width = max(size.width, contentWidth)
        if coordinator.viewportSize != size {
            coordinator.viewportSize = size
            let origin = NSPoint(x: PanoramaMath.clamp(scroll.contentView.bounds.minX, viewport: size.width, extent: width), y: 0)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0
                scroll.contentView.animator().setBoundsOrigin(origin)
            }
        }
        coordinator.host?.frame = NSRect(x: 0, y: 0, width: width, height: max(1, size.height))
        // Avoid publishing observation changes while SwiftUI is updating a view.
        if position.viewport != size.width || position.extent != width {
            DispatchQueue.main.async { position.viewport = max(1, size.width); position.extent = width }
        }
        if coordinator.resetKey != resetKey {
            coordinator.resetKey = resetKey
            scroll.contentView.scroll(to: .zero); scroll.reflectScrolledClipView(scroll.contentView)
        } else if coordinator.request != moveRequest {
            let target = NSPoint(x: min(requestedOffset, max(0, width - size.width)), y: 0)
            if position.reduceMotion { scroll.contentView.scroll(to: target) }
            else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.62
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.1, 0.9, 0.2, 1)
                    scroll.contentView.animator().setBoundsOrigin(target)
                }
            }
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        coordinator.request = moveRequest
        let limit = max(0, width - size.width)
        if scroll.contentView.bounds.origin.x > limit {
            scroll.contentView.scroll(to: NSPoint(x: limit, y: 0)); scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
    static func dismantleNSView(_ view: MusicPanoramaScrollView, coordinator: Coordinator) {
        if let token = coordinator.token { NotificationCenter.default.removeObserver(token) }
    }
    @MainActor final class Coordinator {
        let position: PanoramaPosition
        var host: NSView?
        var token: NSObjectProtocol?
        var resetKey: String?
        var request = 0
        var updating = false
        var viewportSize = CGSize.zero
        init(_ position: PanoramaPosition) { self.position = position }
    }
}

final class MusicPanoramaScrollView: NSScrollView {
    override var acceptsFirstResponder: Bool { true }
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            super.scrollWheel(with: event); return
        }
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 34
        pan(by: -event.scrollingDeltaY * scale)
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: pan(by: -bounds.width * 0.75)
        case 124: pan(by: bounds.width * 0.75)
        default: super.keyDown(with: event)
        }
    }
    private func pan(by delta: CGFloat) {
        let limit = max(0, (documentView?.frame.width ?? 0) - contentSize.width)
        let x = min(limit, max(0, contentView.bounds.minX + delta))
        contentView.scroll(to: NSPoint(x: x, y: 0)); reflectScrolledClipView(contentView)
    }
}

/// Only nearby panels instantiate artwork/tasks. A long provider page must not
/// download every thumbnail or animate tiles outside the visible landscape.
struct PanoramaPanel<Content: View>: View {
    let origin: CGFloat
    let width: CGFloat
    @ViewBuilder var content: () -> Content
    @State private var loaded = false
    var body: some View {
        Group {
            if loaded { content().environment(\.panoramaOrigin, origin) }
            else { Color.clear }
        }.frame(width: width).frame(maxHeight: .infinity, alignment: .top)
            .background { PanoramaProximity(origin: origin, width: width, loaded: $loaded) }
    }
}
private struct PanoramaProximity: View {
    @Environment(PanoramaPosition.self) private var position
    let origin: CGFloat
    let width: CGFloat
    @Binding var loaded: Bool
    var body: some View {
        let nearby = PanoramaMath.nearby(origin: origin, width: width, offset: position.offset, viewport: position.viewport)
        Color.clear.onChange(of: nearby, initial: true) { loaded = nearby }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct PanoramaArtworkOffset: ViewModifier {
    @Environment(PanoramaPosition.self) private var position: PanoramaPosition?
    @Environment(\.panoramaOrigin) private var origin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.offset(x: reduceMotion ? 0 : max(-24, min(24, ((position?.offset ?? origin) - origin) * 0.065)))
    }
}

struct PanoramaBackdrop: View {
    let position: PanoramaPosition
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ChromePattern(accent: accent)
                Text("auralis").font(.system(size: 310, weight: .black)).tracking(-22)
                    .foregroundStyle(accent.opacity(0.025))
                    .offset(x: geometry.size.width * 0.25 - (reduceMotion ? 0 : position.offset * 0.1), y: geometry.size.height * 0.36)
            }
        }.clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct LatticeField: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let unit: CGFloat = 48
        for row in 0...Int(rect.height / unit) + 1 {
            for column in 0...Int(rect.width / unit) + 1 {
                let x = CGFloat(column) * unit, y = CGFloat(row) * unit
                path.move(to: CGPoint(x: x, y: y - 14))
                path.addQuadCurve(to: CGPoint(x: x + 14, y: y), control: CGPoint(x: x + 2, y: y - 2))
                path.addQuadCurve(to: CGPoint(x: x, y: y + 14), control: CGPoint(x: x + 2, y: y + 2))
                path.addQuadCurve(to: CGPoint(x: x - 14, y: y), control: CGPoint(x: x - 2, y: y + 2))
                path.addQuadCurve(to: CGPoint(x: x, y: y - 14), control: CGPoint(x: x - 2, y: y - 2))
                path.move(to: CGPoint(x: x + 17, y: y)); path.addLine(to: CGPoint(x: x + 31, y: y))
            }
        }
        return path
    }
}

struct PanoramaRail: View {
    let position: PanoramaPosition
    let accent: Color
    var label = "scroll to explore"
    var body: some View {
        HStack(spacing: 18) {
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(1.7).foregroundStyle(Color.secondaryInk)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondaryInk.opacity(0.16))
                    Capsule().fill(accent).frame(width: max(32, geometry.size.width * min(1, position.viewport / max(1, position.extent))))
                        .offset(x: max(0, geometry.size.width - max(32, geometry.size.width * min(1, position.viewport / max(1, position.extent)))) * position.progress)
                }
            }.frame(maxWidth: 200).frame(height: 2).accessibilityHidden(true)
            Spacer()
            Button { position.advance(-1) } label: { Image(systemName: "arrow.left").frame(width: 32, height: 28) }.buttonStyle(.plain)
                .accessibilityLabel("Scroll music left").disabled(position.offset <= 1)
            Button { position.advance(1) } label: { Image(systemName: "arrow.right").frame(width: 32, height: 28) }.buttonStyle(.plain)
                .accessibilityLabel("Scroll music right").disabled(position.offset >= position.extent - position.viewport - 1)
        }.foregroundStyle(Color.warmWhite).padding(.horizontal, 36).padding(.vertical, 10)
    }
}

struct PanoramaTitleOffset: ViewModifier {
    let position: PanoramaPosition
    var rate: CGFloat = 0.13
    var limit: CGFloat = 160
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.offset(x: reduceMotion ? 0 : -min(limit, max(0, position.offset) * rate))
    }
}
struct PanoramaSectionOffset: ViewModifier {
    @Environment(PanoramaPosition.self) private var position
    @Environment(\.panoramaOrigin) private var origin
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.offset(x: reduceMotion ? 0 : max(-20, min(24, (position.offset - origin) * 0.11)))
    }
}

struct MusicArrival: ViewModifier {
    var order = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    func body(content: Content) -> some View {
        content.opacity(arrived || reduceMotion ? 1 : 0.2)
            .offset(x: arrived || reduceMotion ? 0 : 28)
            .onAppear { withAnimation(reduceMotion ? nil : MusicMotion.settle.delay(Double(order % 6) * 0.045)) { arrived = true } }
    }
}
