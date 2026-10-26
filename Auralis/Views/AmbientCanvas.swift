import SwiftUI

/// Procedural ambient animation. Time, theme and declared playback state drive motion;
/// there is intentionally no spectrum, amplitude, beat detection, or audio input.
struct AmbientCanvas: View {
    let accent: Color
    let style: AmbientMotion
    let active: Bool
    let lowPower: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = MotionClock()
    private var moving: Bool { !reduceMotion && !lowPower && style != .still && active }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !moving)) { context in
            let time = clock.elapsed(at: context.date)
            Canvas(opaque: false, rendersAsynchronously: true) { canvas, size in
                if style == .ribbons {
                    drawRibbons(context: &canvas, size: size, time: time)
                } else {
                    drawAurora(context: &canvas, size: size, time: time)
                }
            }
        }
        .onChange(of: moving, initial: true) { _, running in clock.setRunning(running) }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
    private func drawAurora(context: inout GraphicsContext, size: CGSize, time: Double) {
        for index in 0..<4 {
            let i = Double(index)
            let center = CGPoint(x: size.width * (0.55 + 0.3 * sin(time * 0.07 + i * 1.8)),
                                 y: size.height * (0.4 + 0.3 * cos(time * 0.05 + i)))
            let radius = max(size.width, size.height) * (0.44 + i * 0.04)
            let color = index.isMultiple(of: 2) ? accent : Color(red: 0.39, green: 0.23, blue: 0.68)
            context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                         with: .radialGradient(Gradient(colors: [color.opacity(0.16), color.opacity(0.03), .clear]), center: center, startRadius: 0, endRadius: radius))
        }
        // A restrained horizon gives the stage depth without simulating audio analysis.
        var line = Path()
        for x in stride(from: 0.0, through: size.width, by: 5) {
            let y = size.height * 0.79 + sin(x / max(1, size.width) * 5.3 + time * 0.08) * size.height * 0.09
            if x == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
        }
        context.stroke(line, with: .color(accent.opacity(0.11)), lineWidth: 1)
    }
    private func drawRibbons(context: inout GraphicsContext, size: CGSize, time: Double) {
        for index in 0..<18 {
            var path = Path()
            let i = Double(index)
            for x in stride(from: -10.0, through: size.width + 10, by: 6) {
                let unit = x / max(1, size.width)
                let y = size.height * (0.56 + 0.22 * sin(unit * 4.1 + time * 0.12 + i * 0.04)) + i * 5
                if x == -10 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .linearGradient(Gradient(colors: [.clear, accent.opacity(0.11 + 0.1 * sin(i / 18 * .pi)), .clear]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)), lineWidth: 1)
        }
    }
}

/// Original artwork for the silent design preview, built with native vector shapes.
struct MotionStudyArt: View {
    let accent: Color
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size.width
            ZStack {
                LinearGradient(colors: [Color(red: 0.15, green: 0.09, blue: 0.2), Color(red: 0.035, green: 0.025, blue: 0.065)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Canvas { context, canvas in
                    let center = CGPoint(x: canvas.width * 0.53, y: canvas.height * 0.49)
                    for i in (0..<36).reversed() {
                        let t = Double(i) / 36
                        let rect = CGRect(x: center.x - canvas.width * (0.12 + t * 0.32),
                                          y: center.y - canvas.height * (0.1 + t * 0.29),
                                          width: canvas.width * (0.24 + t * 0.64), height: canvas.height * (0.2 + t * 0.58))
                        var layer = context
                        layer.translateBy(x: center.x, y: center.y)
                        layer.rotate(by: .degrees(-38 + t * 80))
                        layer.translateBy(x: -center.x, y: -center.y)
                        let color = i % 2 == 0 ? accent : Color(red: 0.68, green: 0.38, blue: 0.85)
                        layer.stroke(Path(roundedRect: rect, cornerRadius: canvas.width * 0.22), with: .color(color.opacity(0.28 + t * 0.6)), lineWidth: 1.2 + t * 1.5)
                    }
                    // Deterministic print texture, rendered once when the view changes.
                    for i in 0..<900 {
                        let x = Double((i * 127 + 43) % 997) / 997 * canvas.width
                        let y = Double((i * 233 + 19) % 991) / 991 * canvas.height
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 0.7, height: 0.7)), with: .color(.white.opacity(0.13)))
                    }
                }
                VStack(alignment: .leading) {
                    HStack { Text("AURALIS").tracking(size * 0.009); Spacer(); Text("001").monospaced() }
                        .font(.system(size: size * 0.024, weight: .medium))
                    Spacer()
                    Text("STILL IN\nMOTION").font(.system(size: size * 0.12, weight: .black, design: .default)).tracking(-size * 0.005).lineSpacing(-size * 0.015)
                    HStack { Text("AN AMBIENT STUDY").tracking(size * 0.004); Spacer(); Image(systemName: "arrow.up.right") }
                        .font(.system(size: size * 0.02, weight: .medium)).padding(.top, size * 0.02)
                }
                .padding(size * 0.075)
                .foregroundStyle(Color(red: 0.98, green: 0.9, blue: 0.84))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Original Auralis geometric motion study artwork. Silent preview.")
    }
}
