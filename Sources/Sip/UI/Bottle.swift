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

/// Where the water sits inside the bottle's outline, treated as a polygon.
enum WaterVolume {
    static func polygon(of path: Path) -> [CGPoint] {
        var points: [CGPoint] = []
        path.cgPath.flattened(threshold: 0.5).applyWithBlock { element in
            let kind = element.pointee.type
            if kind == .moveToPoint || kind == .addLineToPoint { points.append(element.pointee.points[0]) }
        }
        return points
    }

    /// The part of the polygon at or beyond `offset` along the direction `normal`.
    static func below(_ polygon: [CGPoint], along normal: CGPoint, from offset: CGFloat) -> [CGPoint] {
        func depth(_ p: CGPoint) -> CGFloat { p.x * normal.x + p.y * normal.y - offset }
        var result: [CGPoint] = []
        for (index, current) in polygon.enumerated() {
            let next = polygon[(index + 1) % polygon.count]
            let a = depth(current), b = depth(next)
            if a >= 0 { result.append(current) }
            if (a >= 0) != (b >= 0) {
                let t = a / (a - b)
                result.append(CGPoint(x: current.x + (next.x - current.x) * t, y: current.y + (next.y - current.y) * t))
            }
        }
        return result
    }

    static func area(_ polygon: [CGPoint]) -> CGFloat {
        guard polygon.count > 2 else { return 0 }
        var sum: CGFloat = 0
        for (index, p) in polygon.enumerated() {
            let q = polygon[(index + 1) % polygon.count]
            sum += p.x * q.y - q.x * p.y
        }
        return abs(sum) / 2
    }

    /// How far along `normal` the waterline sits so that `area` of water lies beyond it.
    static func waterline(_ polygon: [CGPoint], along normal: CGPoint, area target: CGFloat) -> CGFloat {
        let depths = polygon.map { $0.x * normal.x + $0.y * normal.y }
        var low = depths.min() ?? 0, high = depths.max() ?? 0
        for _ in 0..<22 {
            let middle = (low + high) / 2
            if area(below(polygon, along: normal, from: middle)) > target { low = middle } else { high = middle }
        }
        return (low + high) / 2
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
    /// Follow the Mac's tilt and movement.
    var sloshes = false
    /// How far the cap has been unscrewed, 0 to 1; its ribs slide by as it turns.
    var capTurn = 0.0
    var cap = CapPart.on

    enum CapPart { case on, off, alone }

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
        .background { if sloshes { refraction } }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text("Bottle \(Int((level * 100).rounded())) percent full"))
    }

    /// Clear Liquid Glass along the bottle's sides, where real glass bends the light most, so text and
    /// windows behind it soften and bend at the edges and stay sharp through the middle.
    @ViewBuilder private var refraction: some View {
        if #available(macOS 26, *), !Self.drawsStill {
            Color.clear
                .glassEffect(.clear, in: BottleShape())
                .clipShape(BottleShape())
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.3),
                                             .init(color: .clear, location: 0.7), .init(color: .black, location: 1)],
                                     startPoint: .leading, endPoint: .trailing))
        }
    }

    private func canvas(phase: Double, tilt: Double, agitation: Double) -> some View {
        Canvas { context, size in
            if cap != .alone {
                Self.draw(in: &context, size: size, level: level, phase: phase, tilt: tilt, agitation: agitation)
            }
            if cap != .off { Self.drawCap(in: &context, size: size, turn: capTurn) }
        }
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize, level: Double, phase: Double,
                             tilt: Double, agitation: Double) {
        let rect = CGRect(origin: .zero, size: size)
        let width = size.width, height = size.height
        let outline = BottleShape().path(in: rect)

        drawMouth(in: &context, size: size)

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
            // The surface stays flat at any angle, even with the bottle on its side, and holds the same
            // amount of water: find where the waterline sits so the area under it matches the level.
            let tangent = CGPoint(x: cos(tilt), y: sin(tilt))
            let down = CGPoint(x: -tangent.y, y: tangent.x)
            let glass = WaterVolume.polygon(of: outline)
            let capacity = WaterVolume.area(WaterVolume.below(glass, along: CGPoint(x: 0, y: 1), from: height * 0.22))
            let depth = WaterVolume.waterline(glass, along: down, area: capacity * CGFloat(fill))
            let center = CGPoint(x: down.x * depth, y: down.y * depth)
            let span = max(width, height) * 1.5
            let calm = height * 0.012 * CGFloat(min(1, fill * 8))
            let choppy = calm * CGFloat(agitation) * 2.5
            // Fixed wave speeds: changing a speed mid-flight would make the wave jump.
            func surfacePoint(_ u: CGFloat) -> CGPoint {
                let step = Double(u / width)
                let rise = CGFloat(sin(phase + step * .pi * 2.4)) * calm + CGFloat(sin(phase * 2.6 - step * .pi * 4.2)) * choppy
                return CGPoint(x: center.x + tangent.x * u - down.x * rise, y: center.y + tangent.y * u - down.y * rise)
            }
            var meniscus = Path()
            for u in stride(from: -span, through: span, by: width * 0.02) {
                u == -span ? meniscus.move(to: surfacePoint(u)) : meniscus.addLine(to: surfacePoint(u))
            }
            var surface = meniscus
            surface.addLine(to: CGPoint(x: center.x + tangent.x * span + down.x * span * 2, y: center.y + tangent.y * span + down.y * span * 2))
            surface.addLine(to: CGPoint(x: center.x - tangent.x * span + down.x * span * 2, y: center.y - tangent.y * span + down.y * span * 2))
            surface.closeSubpath()
            // Water is nearly clear too: a light tint, deeper toward the sides where you look through more of it.
            let tint = Color(red: 0.25, green: 0.62, blue: 1)
            let deep = CGPoint(x: center.x + down.x * height * 0.8, y: center.y + down.y * height * 0.8)
            water.fill(surface, with: .linearGradient(Gradient(colors: [tint.opacity(0.28), tint.opacity(0.5)]), startPoint: center, endPoint: deep))
            water.fill(surface, with: across([
                .init(color: tint.opacity(0.45), location: 0.1), .init(color: .clear, location: 0.3),
                .init(color: .clear, location: 0.7), .init(color: tint.opacity(0.4), location: 0.9),
            ]))
            water.stroke(meniscus, with: .color(.white.opacity(0.8)), lineWidth: max(0.6, width * 0.018))
            let shift = max(1, width * 0.03)
            water.stroke(meniscus.offsetBy(dx: down.x * shift, dy: down.y * shift), with: .color(tint.opacity(0.35)), lineWidth: max(0.5, width * 0.012))
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
    }

    /// How far the cap rises from closed to free: the length of the threaded neck under it.
    static let threadLength: CGFloat = 0.094

    /// The threaded glass neck and rounded lip the cap screws onto, hidden under it until it's unscrewed.
    private static func drawMouth(in context: inout GraphicsContext, size: CGSize) {
        let width = size.width, height = size.height
        let dark = Color(red: 0.1, green: 0.16, blue: 0.28).opacity(0.38)
        let neck = Path(CGRect(x: width * 0.355, y: height * 0.03, width: width * 0.29, height: height * 0.08))
        context.fill(neck, with: .linearGradient(
            Gradient(stops: [.init(color: .white.opacity(0.3), location: 0), .init(color: .white.opacity(0.05), location: 0.35),
                             .init(color: .white.opacity(0.05), location: 0.7), .init(color: .white.opacity(0.25), location: 1)]),
            startPoint: CGPoint(x: width * 0.355, y: 0), endPoint: CGPoint(x: width * 0.645, y: 0)))
        context.stroke(neck, with: .color(dark), lineWidth: max(1, width * 0.02))
        context.stroke(neck, with: .color(.white.opacity(0.7)), lineWidth: max(0.5, width * 0.008))
        // The thread winds around the neck, so each turn shows as a slanted ridge.
        for step in 0..<4 {
            let y = height * (0.052 + CGFloat(step) * 0.014)
            context.stroke(Path { $0.move(to: CGPoint(x: width * 0.355, y: y + height * 0.006)); $0.addLine(to: CGPoint(x: width * 0.645, y: y)) },
                           with: .color(.white.opacity(0.6)), lineWidth: max(0.8, width * 0.016))
        }
        // A ring where the neck meets the bottle, and a rounded lip with the opening at the top.
        let ring = Path(roundedRect: CGRect(x: width * 0.335, y: height * 0.098, width: width * 0.33, height: height * 0.014), cornerRadius: width * 0.02)
        context.fill(ring, with: .color(.white.opacity(0.3)))
        context.stroke(ring, with: .color(dark), lineWidth: max(0.6, width * 0.01))
        let lip = Path(roundedRect: CGRect(x: width * 0.34, y: height * 0.022, width: width * 0.32, height: height * 0.018), cornerRadius: height * 0.009)
        context.fill(lip, with: .color(.white.opacity(0.35)))
        context.stroke(lip, with: .color(dark), lineWidth: max(0.6, width * 0.012))
        context.stroke(lip, with: .color(.white.opacity(0.85)), lineWidth: max(0.5, width * 0.007))
        context.fill(Path(ellipseIn: CGRect(x: width * 0.38, y: height * 0.026, width: width * 0.24, height: height * 0.008)),
                     with: .color(Color(red: 0.05, green: 0.1, blue: 0.2).opacity(0.5)))
    }

    /// A ribbed navy screw cap with a rolled lip. Turning it slides the ribs across, like a real one spinning.
    private static func drawCap(in context: inout GraphicsContext, size: CGSize, turn: Double) {
        let width = size.width, height = size.height
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
        let spacing = width * 0.034
        var x = capRect.minX + width * 0.03 - spacing + spacing * CGFloat((turn * 14).truncatingRemainder(dividingBy: 1))
        while x < capRect.maxX - width * 0.01 {
            ribs.fill(Path(CGRect(x: x, y: capRect.minY + height * 0.012, width: max(0.4, width * 0.008), height: capRect.height * 0.72)),
                      with: .color(.black.opacity(0.35)))
            x += spacing
        }
        ribs.fill(Path(CGRect(x: capRect.minX, y: capRect.maxY - height * 0.018, width: capRect.width, height: height * 0.018)),
                  with: .color(Color(red: 0.25, green: 0.4, blue: 0.8).opacity(0.7)))
        ribs.fill(Path(CGRect(x: capRect.minX, y: 0, width: capRect.width, height: max(0.6, height * 0.006))), with: .color(.white.opacity(0.3)))
    }
}
