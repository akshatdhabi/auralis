import SwiftUI

private struct ChromeClockKey: EnvironmentKey { static let defaultValue = MotionClock() }
extension EnvironmentValues {
    var chromeClock: MotionClock {
        get { self[ChromeClockKey.self] }
        set { self[ChromeClockKey.self] = newValue }
    }
}

/// The same Jaali lattice as the landscape, drifting gently behind the chrome.
/// The animation is isolated from controls and never intercepts pointer input.
struct ChromePattern: View {
    let accent: Color
    @Environment(\.chromeClock) private var clock

    var body: some View {
        GeometryReader { geometry in
            let origin = geometry.frame(in: .named("AuralisWindow")).origin
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !clock.isRunning)) { timeline in
                let time = clock.elapsed(at: timeline.date)
                Canvas(rendersAsynchronously: true) { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.ink))
                    let center = CGPoint(x: size.width * (0.42 + 0.15 * sin(time * 0.035)) - origin.x, y: -origin.y)
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                        Gradient(colors: [accent.opacity(0.11), .clear]), center: center,
                        startRadius: 0, endRadius: max(size.width * 0.7, 1)))
                    context.translateBy(x: -(origin.x + CGFloat(time * 2)).truncatingRemainder(dividingBy: 48),
                                        y: -(origin.y + CGFloat(time * 0.65)).truncatingRemainder(dividingBy: 48))
                    context.stroke(LatticeField().path(in: CGRect(x: 0, y: 0, width: size.width + 96, height: size.height + 96)),
                                   with: .color(accent.opacity(0.15)), lineWidth: 0.65)
                }
            }
        }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}
