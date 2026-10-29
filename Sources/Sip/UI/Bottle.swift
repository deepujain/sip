import SwiftUI

/// The outline of a sports bottle, below the cap, in a unit rectangle.
struct BottleShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: point(0.37, 0.085))
        path.addLine(to: point(0.63, 0.085))
        path.addLine(to: point(0.63, 0.15))
        path.addCurve(to: point(0.9, 0.31), control1: point(0.63, 0.21), control2: point(0.9, 0.22))
        path.addLine(to: point(0.9, 0.9))
        path.addQuadCurve(to: point(0.77, 1), control: point(0.9, 1))
        path.addLine(to: point(0.23, 1))
        path.addQuadCurve(to: point(0.1, 0.9), control: point(0.1, 1))
        path.addLine(to: point(0.1, 0.31))
        path.addCurve(to: point(0.37, 0.15), control1: point(0.1, 0.22), control2: point(0.37, 0.21))
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

    /// Image rendering can't draw a timeline, so snapshots draw the water still.
    nonisolated(unsafe) static var drawsStill = false

    static let aspect: CGFloat = 0.42

    var body: some View {
        Group {
            if animated && !Self.drawsStill {
                TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                    canvas(phase: context.date.timeIntervalSinceReferenceDate * 1.7)
                }
            } else {
                canvas(phase: 0.8)
            }
        }
        .aspectRatio(Self.aspect, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(Text("Bottle \(Int((level * 100).rounded())) percent full"))
    }

    private func canvas(phase: Double) -> some View {
        Canvas { context, size in
            Self.draw(in: &context, size: size, level: level, phase: phase, warning: warning)
        }
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize, level: Double, phase: Double, warning: Bool) {
        let rect = CGRect(origin: .zero, size: size)
        let width = size.width, height = size.height
        let outline = BottleShape().path(in: rect)

        context.fill(outline, with: .linearGradient(
            Gradient(colors: [Color(red: 0.86, green: 0.94, blue: 1).opacity(0.75), Color(red: 0.74, green: 0.86, blue: 0.98).opacity(0.6)]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: width, y: 0)))

        let fill = min(1, max(0, level))
        if fill > 0.002 {
            var water = context
            water.clip(to: outline)
            let top = height * (0.985 - CGFloat(fill) * 0.785)
            let wave = height * 0.012 * CGFloat(min(1, fill * 8))
            var surface = Path()
            surface.move(to: CGPoint(x: 0, y: height))
            for step in stride(from: CGFloat(0), through: 1, by: 0.02) {
                surface.addLine(to: CGPoint(x: width * step, y: top + sin(phase + Double(step) * .pi * 2.4) * wave))
            }
            surface.addLine(to: CGPoint(x: width, y: height))
            surface.closeSubpath()
            let colors = warning
                ? [Color(red: 1, green: 0.72, blue: 0.4), Color(red: 0.95, green: 0.45, blue: 0.18)]
                : [Color(red: 0.42, green: 0.79, blue: 1), Color(red: 0.07, green: 0.45, blue: 0.95)]
            water.fill(surface, with: .linearGradient(Gradient(colors: colors),
                                                      startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: height)))
            var foam = Path()
            for step in stride(from: CGFloat(0), through: 1, by: 0.02) {
                let point = CGPoint(x: width * step, y: top + sin(phase + Double(step) * .pi * 2.4) * wave)
                step == 0 ? foam.move(to: point) : foam.addLine(to: point)
            }
            water.stroke(foam, with: .color(.white.opacity(0.55)), lineWidth: max(0.5, width * 0.02))
        }

        for mark in 1..<4 {
            let y = height * (0.985 - CGFloat(mark) * 0.785 / 4)
            let tick = Path(roundedRect: CGRect(x: width * 0.68, y: y - width * 0.01, width: width * 0.14, height: max(0.8, width * 0.02)),
                            cornerRadius: width * 0.01)
            context.fill(tick, with: .color(Color(red: 0.2, green: 0.4, blue: 0.65).opacity(0.35)))
        }

        let shine = Path(roundedRect: CGRect(x: width * 0.19, y: height * 0.38, width: width * 0.07, height: height * 0.48),
                         cornerRadius: width * 0.035)
        context.fill(shine, with: .color(.white.opacity(0.55)))

        context.stroke(outline, with: .color(Color(red: 0.15, green: 0.32, blue: 0.55).opacity(0.45)), lineWidth: max(1, width * 0.028))
        context.stroke(outline, with: .color(.white.opacity(0.7)), lineWidth: max(0.5, width * 0.01))

        let cap = Path(roundedRect: CGRect(x: width * 0.33, y: 0, width: width * 0.34, height: height * 0.095),
                       cornerRadius: width * 0.06)
        context.fill(cap, with: .linearGradient(
            Gradient(colors: [Color(red: 0.32, green: 0.6, blue: 0.98), Color(red: 0.1, green: 0.36, blue: 0.85)]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: height * 0.095)))
        let ridge = Path(CGRect(x: width * 0.33, y: height * 0.07, width: width * 0.34, height: max(0.6, height * 0.006)))
        context.fill(ridge, with: .color(.white.opacity(0.35)))
    }
}
