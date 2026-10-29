import SwiftUI

/// The outline of a glass bottle below the cap: short neck, round shoulders, straight sides, in a unit rectangle.
struct BottleShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: point(0.35, 0.1))
        path.addLine(to: point(0.65, 0.1))
        path.addLine(to: point(0.65, 0.155))
        path.addCurve(to: point(0.9, 0.31), control1: point(0.65, 0.215), control2: point(0.9, 0.215))
        path.addLine(to: point(0.9, 0.94))
        path.addQuadCurve(to: point(0.8, 1), control: point(0.9, 1))
        path.addLine(to: point(0.2, 1))
        path.addQuadCurve(to: point(0.1, 0.94), control: point(0.1, 1))
        path.addLine(to: point(0.1, 0.31))
        path.addCurve(to: point(0.35, 0.155), control1: point(0.1, 0.215), control2: point(0.35, 0.215))
        path.closeSubpath()
        return path
    }
}

/// A bottle with water up to `level` (0 empty, 1 full), drawn in one pass so it looks the same everywhere.
struct BottleView: View, Animatable {
    var level: Double
    var animatableData: Double {
        get { level }
        set { level = newValue }
    }
    var animated = true
    var warning = false
    /// Follow the Mac's tilt and movement.
    var sloshes = false

    /// Image rendering can't draw a timeline, so snapshots draw the water still.
    nonisolated(unsafe) static var drawsStill = false

    static let aspect: CGFloat = 0.38

    var body: some View {
        Group {
            if animated && !Self.drawsStill {
                TimelineView(.animation(minimumInterval: sloshes ? 1 / 60 : 1 / 20)) { context in
                    canvas(phase: context.date.timeIntervalSinceReferenceDate * 1.7,
                           // The bottle itself leans too, so the surface turns by that much more against it.
                           tilt: sloshes ? Slosh.shared.tilt + Slosh.shared.lean : 0,
                           agitation: sloshes ? Slosh.shared.agitation : 0)
                }
            } else {
                canvas(phase: 0.8, tilt: 0, agitation: 0)
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text("Bottle \(Int((level * 100).rounded())) percent full"))
    }

    private func canvas(phase: Double, tilt: Double, agitation: Double) -> some View {
        Canvas { context, size in
            Self.draw(in: &context, size: size, level: level, phase: phase, warning: warning, tilt: tilt, agitation: agitation)
        }
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize, level: Double, phase: Double, warning: Bool,
                             tilt: Double, agitation: Double) {
        let rect = CGRect(origin: .zero, size: size)
        let width = size.width, height = size.height
        let outline = BottleShape().path(in: rect)

        // Clear glass: whatever is behind shows through. A cylinder catches light at its edges, not its middle.
        let across = { (stops: [Gradient.Stop]) in
            GraphicsContext.Shading.linearGradient(Gradient(stops: stops), startPoint: .zero, endPoint: CGPoint(x: width, y: 0))
        }
        context.fill(outline, with: .color(.white.opacity(0.06)))
        context.fill(outline, with: across([
            .init(color: .white.opacity(0.3), location: 0.08), .init(color: .white.opacity(0.04), location: 0.22),
            .init(color: .clear, location: 0.5), .init(color: .white.opacity(0.03), location: 0.78),
            .init(color: .white.opacity(0.24), location: 0.92),
        ]))

        let fill = min(1, max(0, level))
        if fill > 0.002 {
            var water = context
            water.clip(to: outline)
            let top = height * (0.965 - CGFloat(fill) * 0.745)
            let calm = height * 0.012 * CGFloat(min(1, fill * 8))
            let choppy = calm * CGFloat(agitation) * 2.5
            let slope = CGFloat(tan(tilt))
            // Fixed wave speeds: changing a speed mid-flight would make the wave jump.
            func surfaceY(_ step: CGFloat) -> CGFloat {
                top + slope * (width * step - width / 2)
                    + CGFloat(sin(phase + Double(step) * .pi * 2.4)) * calm
                    + CGFloat(sin(phase * 2.6 - Double(step) * .pi * 4.2)) * choppy
            }
            var surface = Path()
            surface.move(to: CGPoint(x: 0, y: height))
            for step in stride(from: CGFloat(0), through: 1, by: 0.02) {
                surface.addLine(to: CGPoint(x: width * step, y: surfaceY(step)))
            }
            surface.addLine(to: CGPoint(x: width, y: height))
            surface.closeSubpath()
            // Water is nearly clear too: a light tint, deeper toward the sides where you look through more of it.
            let tint = warning ? Color(red: 1, green: 0.6, blue: 0.25) : Color(red: 0.25, green: 0.62, blue: 1)
            water.fill(surface, with: .linearGradient(Gradient(colors: [tint.opacity(0.28), tint.opacity(0.5)]),
                                                      startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: height)))
            water.fill(surface, with: across([
                .init(color: tint.opacity(0.45), location: 0.1), .init(color: .clear, location: 0.3),
                .init(color: .clear, location: 0.7), .init(color: tint.opacity(0.4), location: 0.9),
            ]))
            var meniscus = Path()
            for step in stride(from: CGFloat(0), through: 1, by: 0.02) {
                let point = CGPoint(x: width * step, y: surfaceY(step))
                step == 0 ? meniscus.move(to: point) : meniscus.addLine(to: point)
            }
            water.stroke(meniscus, with: .color(.white.opacity(0.8)), lineWidth: max(0.6, width * 0.018))
            water.stroke(meniscus.offsetBy(dx: 0, dy: max(1, width * 0.03)), with: .color(tint.opacity(0.35)), lineWidth: max(0.5, width * 0.012))
        }

        // The thick glass base.
        var base = context
        base.clip(to: outline)
        base.fill(Path(CGRect(x: 0, y: height * 0.965, width: width, height: height * 0.035)), with: .color(.white.opacity(0.22)))
        base.stroke(Path { $0.move(to: CGPoint(x: width * 0.12, y: height * 0.965)); $0.addLine(to: CGPoint(x: width * 0.88, y: height * 0.965)) },
                    with: .color(.white.opacity(0.45)), lineWidth: max(0.5, width * 0.01))

        // Long reflections down both sides, brightest in the middle, like a window on curved glass.
        func streak(x: CGFloat, w: CGFloat, top: CGFloat, bottom: CGFloat, strength: Double) {
            let rect = CGRect(x: width * x, y: height * top, width: width * w, height: height * (bottom - top))
            context.fill(Path(roundedRect: rect, cornerRadius: width * w / 2), with: .linearGradient(
                Gradient(stops: [.init(color: .white.opacity(0), location: 0), .init(color: .white.opacity(strength), location: 0.3),
                                 .init(color: .white.opacity(strength), location: 0.7), .init(color: .white.opacity(0), location: 1)]),
                startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
        }
        streak(x: 0.16, w: 0.07, top: 0.3, bottom: 0.93, strength: 0.6)
        streak(x: 0.79, w: 0.03, top: 0.34, bottom: 0.88, strength: 0.4)
        streak(x: 0.4, w: 0.035, top: 0.11, bottom: 0.2, strength: 0.45)

        // A dark rim and a bright one, so clear glass still reads on light and dark desktops alike.
        context.stroke(outline, with: .color(Color(red: 0.1, green: 0.16, blue: 0.28).opacity(0.38)), lineWidth: max(1, width * 0.024))
        context.stroke(outline, with: .color(.white.opacity(0.75)), lineWidth: max(0.5, width * 0.009))

        // A ribbed navy screw cap with a rolled lip.
        let capRect = CGRect(x: width * 0.31, y: 0, width: width * 0.38, height: height * 0.112)
        let cap = Path(roundedRect: capRect, cornerRadius: width * 0.045)
        context.fill(cap, with: .linearGradient(
            Gradient(stops: [.init(color: Color(red: 0.03, green: 0.07, blue: 0.24), location: 0),
                             .init(color: Color(red: 0.18, green: 0.32, blue: 0.72), location: 0.3),
                             .init(color: Color(red: 0.09, green: 0.18, blue: 0.48), location: 0.6),
                             .init(color: Color(red: 0.02, green: 0.05, blue: 0.18), location: 1)]),
            startPoint: CGPoint(x: capRect.minX, y: 0), endPoint: CGPoint(x: capRect.maxX, y: 0)))
        var ribs = context
        ribs.clip(to: cap)
        var x = capRect.minX + width * 0.03
        while x < capRect.maxX - width * 0.01 {
            ribs.fill(Path(CGRect(x: x, y: capRect.minY + height * 0.012, width: max(0.4, width * 0.008), height: capRect.height * 0.72)),
                      with: .color(.black.opacity(0.35)))
            x += width * 0.034
        }
        ribs.fill(Path(CGRect(x: capRect.minX, y: capRect.maxY - height * 0.018, width: capRect.width, height: height * 0.018)),
                  with: .color(Color(red: 0.25, green: 0.4, blue: 0.8).opacity(0.7)))
        ribs.fill(Path(CGRect(x: capRect.minX, y: 0, width: capRect.width, height: max(0.6, height * 0.006))), with: .color(.white.opacity(0.3)))
    }
}
