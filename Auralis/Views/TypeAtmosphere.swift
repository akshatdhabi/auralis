import SwiftUI

/// A typographic visualizer, not an audio analyzer. All words have an explicit
/// source; movement comes only from a paused/resumable clock and playback state.
struct TypeAtmosphere: View {
    let title: String
    let artist: String
    let phrases: [String]
    let accent: Color
    let active: Bool
    let lowPower: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = MotionClock()
    private var enabled: Bool { active && !lowPower && !reduceMotion }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !enabled)) { timeline in
            let time = clock.elapsed(at: timeline.date)
            Canvas { context, size in
                let words = phrases.isEmpty ? [title, artist] : phrases
                guard !words.isEmpty else { return }
                for index in 0..<7 {
                    let phrase = words[index % words.count]
                    let headline = index == 0 || index == 4
                    let fontSize = headline ? min(210, size.width * 0.15) : min(54, size.width * 0.043)
                    let drift = time * (index.isMultiple(of: 2) ? 9.0 : -6.0)
                    let period = max(1, size.width * 1.9)
                    let phase = (CGFloat(index) * size.width * 0.31 + drift).truncatingRemainder(dividingBy: period)
                    let x = phase < 0 ? phase + period : phase
                    let y = size.height * (0.10 + Double(index) * 0.145) + sin(time * 0.08 + Double(index)) * 18
                    var layer = context
                    layer.opacity = headline ? 0.075 : 0.105
                    layer.translateBy(x: x, y: y)
                    layer.rotate(by: .degrees(index.isMultiple(of: 2) ? -8 : 5))
                    let text = Text(String(phrase.prefix(headline ? 60 : 100))).font(.system(size: fontSize, weight: headline ? .black : .semibold)).tracking(headline ? -6 : -1)
                        .foregroundColor(index.isMultiple(of: 3) ? accent : Color.warmWhite)
                    layer.draw(text, at: .zero, anchor: .leading)
                    layer.draw(text, at: CGPoint(x: -period, y: 0), anchor: .leading)
                }
            }
        }
        .onChange(of: enabled, initial: true) { _, running in clock.setRunning(running) }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}
