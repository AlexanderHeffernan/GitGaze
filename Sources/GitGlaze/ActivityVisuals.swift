import SwiftUI
import CoreText

enum CelebrationStyle: String, CaseIterable, Identifiable {
    case fireworks, nova, meteors
    var id: String { rawValue }
    var title: String { switch self { case .fireworks: "Fireworks"; case .nova: "Supernova"; case .meteors: "Meteor shower" } }
    var symbol: String { switch self { case .fireworks: "sparkles"; case .nova: "sun.max"; case .meteors: "sparkle" } }
}

/// The same record instrument at dashboard and menu-bar scale. No artificial daily target.
struct RecordDial: View {
    let progress: Double
    let active: Bool
    var record = false
    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let miniature = diameter < 30
            let steps = miniature ? 16 : 40
            let lit = active ? max(1, Int(ceil(min(1, max(0, progress)) * Double(steps)))) : 0
            Canvas { context, size in
                for index in 0..<steps {
                    var tick = context
                    tick.translateBy(x: size.width / 2, y: size.height / 2)
                    tick.rotate(by: .radians(Double(index) / Double(steps) * .pi * 2))
                    let rect = CGRect(x: miniature ? -0.65 : -1.5, y: -diameter / 2 + 1,
                        width: miniature ? 1.3 : 3, height: miniature ? 3 : 8)
                    let color = index < lit ? (record ? Theme.gold : Theme.accent) : Color.primary.opacity(miniature ? 0.36 : 0.16)
                    tick.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(color))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct ChargeOutline: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 7, y: rect.minY + 0.5))
            path.addLine(to: CGPoint(x: rect.maxX - 0.5, y: rect.minY + 0.5))
            path.addLine(to: CGPoint(x: rect.maxX - 7, y: rect.maxY - 0.5))
            path.addLine(to: CGPoint(x: 0.5, y: rect.maxY - 0.5))
            path.closeSubpath()
        }
    }
}

/// Three timed, deterministic bursts: comet launch, expanding shockwave, glowing trails, then falling confetti.
/// Rendering is time-based so it stays smooth without particle state.
struct Fireworks: View {
    var anchorX: CGFloat = 220
    var animated = true
    var style = "fireworks"
    var count = 3
    var record = false
    private let glyph: [CGPoint]
    init(anchorX: CGFloat = 220, animated: Bool = true, style: String = "fireworks", count: Int = 3, record: Bool = false) {
        self.anchorX = anchorX; self.animated = animated; self.style = style; self.count = count; self.record = record
        glyph = Self.letterParticles("+\(count)")
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || !animated)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(started)
            Canvas { context, size in
                guard !reduceMotion, animated, elapsed < 4.7 else { return }
                let center = CGPoint(x: min(max(170, anchorX), size.width - 170), y: 145)
                if style != "fireworks" {
                    drawAlternate(context: &context, size: size, elapsed: elapsed)
                } else {
                if elapsed < 0.7 {
                    let p = min(1, elapsed / 0.7)
                    for ember in 0..<12 {
                        let y = -10 + (center.y + 10) * (1 - pow(1 - max(0, p - Double(ember) * 0.013), 3))
                        let radius = max(0.6, 3.6 - Double(ember) * 0.23)
                        context.opacity = 1 - Double(ember) / 13
                        context.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(ember == 0 ? .white : Theme.accent))
                    }
                }
                for burst in 0..<3 {
                    let age = elapsed - [0.65, 0.94, 1.2][burst]
                    guard age > 0, age < 2.4 else { continue }
                    let origin = CGPoint(x: center.x + [0.0, -75, 72][burst], y: center.y + [0.0, 30, 16][burst])
                    let spread = 1 - pow(1 - min(1, age / 1.8), 3)
                    let fade = min(1, max(0, (2.4 - age) / 0.9))
                    var flash = context
                    flash.opacity = max(0, 1 - age / 0.65)
                    let halo = CGRect(x: origin.x - 48, y: origin.y - 48, width: 96, height: 96)
                    flash.fill(Path(ellipseIn: halo), with: .radialGradient(
                        Gradient(colors: [.white.opacity(0.65), Theme.accent.opacity(0.25), .clear]),
                        center: origin, startRadius: 0, endRadius: 48))
                    var wave = context
                    wave.opacity = max(0, 1 - age / 0.7) * 0.25
                    wave.addFilter(.blur(radius: 2))
                    wave.stroke(Path(ellipseIn: CGRect(x: origin.x - age * 135, y: origin.y - age * 135, width: age * 270, height: age * 270)), with: .color(Theme.accent), lineWidth: 3)
                    for index in 0..<96 {
                        let angle = Double(index) * .pi * 2 / 96 + Double(index % 7) * 0.019
                        let distance = Double(40 + (index * 29) % 78) * (burst == 0 ? 1 : 0.72)
                        let x = origin.x + cos(angle) * distance * spread
                        let y = origin.y + sin(angle) * distance * spread + age * age * 31
                        let color: Color = index.isMultiple(of: 7) ? .white : index.isMultiple(of: 4) ? Theme.gold : Theme.accent
                        context.opacity = fade * (index.isMultiple(of: 3) ? 0.9 : 0.65)
                        if index.isMultiple(of: 3) {
                            var trail = Path()
                            trail.move(to: CGPoint(x: x - cos(angle) * 15 * (1 - age / 3), y: y - sin(angle) * 15 * (1 - age / 3)))
                            trail.addLine(to: CGPoint(x: x, y: y))
                            context.stroke(trail, with: .color(color), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        }
                        var glow = context
                        glow.opacity = fade * 0.3
                        glow.addFilter(.blur(radius: 2.5))
                        glow.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(color))
                        context.opacity = fade
                        var particle = context
                        particle.translateBy(x: x, y: y)
                        particle.rotate(by: .radians(angle + age * (index.isMultiple(of: 2) ? 2 : -2)))
                        particle.fill(Path(roundedRect: CGRect(x: -1, y: -1, width: index.isMultiple(of: 4) ? 5 : 2, height: 2), cornerRadius: 0.7), with: .color(color))
                    }
                }
                }
                drawNumber(context: context, center: center, size: size, elapsed: elapsed)
            }
        }.mask {
            Rectangle().fill(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.12), .init(color: .white, location: 0.88), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.12), .init(color: .white, location: 0.86), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
        }.allowsHitTesting(false).accessibilityHidden(true)
    }

    /// Sample actual font outlines once, not per frame. These sparks are the number, not a text overlay.
    private static func letterParticles(_ text: String) -> [CGPoint] {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 62, weight: .bold)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        let outline = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            for index in 0..<count {
                if let path = CTFontCreatePathForGlyph(runFont, glyphs[index], nil) {
                    outline.addPath(path, transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y))
                }
            }
        }
        let bounds = outline.boundingBoxOfPath
        let scale = min(1, 230 / max(1, bounds.width))
        var points: [CGPoint] = []
        for y in stride(from: bounds.minY, through: bounds.maxY, by: 2.4 / scale) {
            for x in stride(from: bounds.minX, through: bounds.maxX, by: 2.4 / scale) where outline.contains(CGPoint(x: x, y: y)) {
                points.append(CGPoint(x: (x - bounds.midX) * scale, y: (bounds.midY - y) * scale))
            }
        }
        return points
    }

    private func edgeOpacity(x: CGFloat, y: CGFloat, size: CGSize, inset: CGFloat) -> Double {
        let distance = min(x, y, size.width - x, size.height - y)
        let p = Double(min(1, max(0, (distance - inset) / 48)))
        return p * p * (3 - 2 * p)
    }

    private func drawNumber(context: GraphicsContext, center: CGPoint, size: CGSize, elapsed: Double) {
        let accent = record ? Theme.gold : Theme.accent
        var sparks = context
        sparks.opacity = 1
        let fade = min(1, max(0, (4.5 - elapsed) / 0.8))
        for (index, point) in glyph.enumerated() {
            let age = elapsed - 0.65 - Double(index % 9) * 0.018
            guard age > 0 else { continue }
            let angle = Double(index) * 2.39996
            let gather = min(1, max(0, (age - 0.25) / 1.05))
            let eased = gather * gather * (3 - 2 * gather)
            let radius = Double(65 + index % 83)
            let origin: CGPoint
            if style == "meteors" {
                origin = CGPoint(x: point.x + 160 + Double(index % 7) * 9, y: point.y - 160 - Double(index % 11) * 6)
            } else {
                let spread = style == "nova" ? 1 : min(1, age / 0.25)
                origin = CGPoint(x: cos(angle) * radius * spread, y: sin(angle) * radius * spread)
            }
            let dissolve = max(0, elapsed - 3.5)
            let x = center.x + origin.x * (1 - eased) + point.x * eased + cos(angle) * dissolve * dissolve * 30
            let y = center.y + origin.y * (1 - eased) + point.y * eased + sin(angle) * dissolve * dissolve * 30
            let opacity = min(1, age * 5) * fade * edgeOpacity(x: x, y: y, size: size, inset: 12)
            sparks.opacity = opacity * 0.22
            sparks.fill(Path(ellipseIn: CGRect(x: x - 3.3, y: y - 3.3, width: 6.6, height: 6.6)), with: .color(accent))
            sparks.opacity = opacity * (0.82 + 0.18 * sin(elapsed * 5 + Double(index)))
            sparks.fill(Path(ellipseIn: CGRect(x: x - 0.95, y: y - 0.95, width: 1.9, height: 1.9)), with: .color(index.isMultiple(of: 5) ? .white : accent))
        }
    }

    private func drawAlternate(context: inout GraphicsContext, size: CGSize, elapsed: Double) {
        let center = CGPoint(x: size.width / 2, y: 145)
        let fade = min(1, max(0, (3.7 - elapsed) / 1.2))
        if style == "nova" {
            let radius = elapsed < 0.65 ? 150 * pow(1 - elapsed / 0.65, 2) : 135 * (1 - exp(-(elapsed - 0.65) * 2.5))
            for index in 0..<84 {
                let angle = Double(index) * .pi * 2 / 84 + elapsed * 0.3
                let orbit = radius + sin(Double(index) * 2.1) * 14
                let point = CGPoint(x: center.x + cos(angle) * orbit, y: center.y + sin(angle) * orbit * 0.8)
                let color: Color = index.isMultiple(of: 4) ? Theme.gold : Theme.accent
                var glow = context; glow.opacity = fade * 0.35; glow.addFilter(.blur(radius: 4))
                glow.fill(Path(ellipseIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)), with: .color(color))
                context.opacity = fade
                context.fill(Path(ellipseIn: CGRect(x: point.x - 1.4, y: point.y - 1.4, width: 2.8, height: 2.8)), with: .color(index.isMultiple(of: 5) ? .white : color))
            }
            let flash = max(0, 1 - abs(elapsed - 0.7) / 0.35)
            context.opacity = flash
            context.fill(Path(ellipseIn: CGRect(x: center.x - 100, y: center.y - 100, width: 200, height: 200)), with: .radialGradient(Gradient(colors: [.white.opacity(0.65), Theme.accent.opacity(0.2), .clear]), center: center, startRadius: 0, endRadius: 100))
        } else {
            for index in 0..<48 {
                let age = elapsed - Double(index % 12) * 0.075
                guard age > 0 else { continue }
                let x = Double((index * 67) % 440) + 160 - age * 130
                let y = Double((index * 37) % 180) - 150 + age * 135
                let length = Double(14 + index % 5 * 5)
                var streak = Path(); streak.move(to: CGPoint(x: x + length, y: y - length)); streak.addLine(to: CGPoint(x: x, y: y))
                let color: Color = index.isMultiple(of: 4) ? Theme.gold : Theme.accent
                // Fade the whole trail before either end reaches the panel boundary, including its glow.
                let visibility = fade * edgeOpacity(x: x, y: y, size: size, inset: 44)
                var glow = context; glow.opacity = visibility * 0.35; glow.addFilter(.blur(radius: 3))
                glow.stroke(streak, with: .color(color), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                context.opacity = visibility * 0.85
                context.stroke(streak, with: .linearGradient(Gradient(colors: [.clear, color, .white]), startPoint: CGPoint(x: x + length, y: y - length), endPoint: CGPoint(x: x, y: y)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
    }
}

struct CelebrationView: View {
    let count: Int
    let record: Bool
    var sample = false
    var anchorX: CGFloat = 220
    var animated = true
    var style = "fireworks"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            if reduceMotion || !animated {
                Text("+\(count)").font(.system(size: 32, weight: .semibold, design: .rounded))
                    .foregroundStyle((record ? Theme.gold : Theme.accent).gradient)
            } else {
                Fireworks(anchorX: anchorX, animated: animated, style: style, count: count, record: record)
            }
        }.frame(width: 440, height: reduceMotion || !animated ? 90 : 340)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(sample ? "Preview celebration, sample data" : "\(count) new contributions confirmed. \(record ? "New daily best." : "")")
    }
}
