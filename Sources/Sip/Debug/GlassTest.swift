#if DEBUG
import AppKit
import SwiftUI

/// Puts glass bottle variants over a window of text so a screen capture can compare them: `Sip --glass-test`.
@MainActor
enum GlassTest {
    static let origin = CGPoint(x: 200, y: 200)
    static let size = CGSize(width: 700, height: 260)

    static func show() {
        let text = window(level: .floating)
        text.contentView = NSHostingView(rootView: Lines())
        text.orderFrontRegardless()
        let bottles = window(level: .statusBar)
        bottles.isOpaque = false
        bottles.backgroundColor = .clear
        bottles.contentView = NSHostingView(rootView: Variants())
        bottles.orderFrontRegardless()
    }

    private static func window(level: NSWindow.Level) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: origin, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = level
        window.isReleasedWhenClosed = false
        return window
    }
}

private struct Lines: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(0..<9) { line in
                Text("Bottle 3 of 4 · finish by 5:30 PM — The quick brown fox jumps over the lazy dog \(line)")
                    .font(.system(size: 17, weight: line % 3 == 0 ? .bold : .regular))
                    .foregroundStyle(line % 2 == 0 ? Color.white : Color.orange)
            }
        }
        .padding(16)
        .frame(width: GlassTest.size.width, height: GlassTest.size.height, alignment: .topLeading)
        .background(Color(red: 0.12, green: 0.12, blue: 0.16))
    }
}

private struct Variants: View {
    var body: some View {
        HStack(spacing: 60) {
            BottleView(level: 0.5, sloshes: false).frame(height: 200)
            ForEach([0.0, 30, 80], id: \.self) { angle in
                BottleView(level: 0.5, sloshes: true)
                    .frame(height: 200)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                    .rotationEffect(.degrees(-angle), anchor: UnitPoint(x: 0.1, y: 1))
                    .scaleEffect(1.04, anchor: .bottom)
            }
        }
        .frame(width: GlassTest.size.width, height: GlassTest.size.height)
    }
}
#endif
