import AppKit
import SwiftUI

/// The card that slides in under the menu bar: halfway through a bottle, and when it's due.
struct NudgeView: View {
    let model: WaterModel
    let nudge: Nudge
    static let width: CGFloat = 356

    private var slot: Slot {
        switch nudge {
        case .halfway(let slot), .due(let slot): slot
        }
    }

    private var isDue: Bool {
        if case .due = nudge { return true }
        return false
    }

    private var title: String {
        isDue ? "Is bottle \(slot.number) empty?" : "Halfway through bottle \(slot.number)"
    }

    private var message: String {
        if !isDue { return "It should be about half gone by now. Finish it by \(Fmt.time(slot.end))." }
        guard model.dryspell else { return "It was due at \(Fmt.time(slot.end))." }
        return "It was due at \(Fmt.time(slot.end)). Finish it by \(Fmt.time(model.lockAt(slot))) to keep your Mac unlocked."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BottleView(level: isDue ? 0.12 : 0.5, warning: isDue)
                .frame(height: 64)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    PillButton(title: isDue ? "Yes, it’s empty" : "Already empty", prominent: true) { model.finishBottle() }
                    PillButton(title: isDue ? "Not yet" : "OK", prominent: false) { model.dismissNudge() }
                }
                .padding(.top, 8)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .padding(20)
    }
}

/// Drawn by SwiftUI, not AppKit, so it answers the first click in a panel that never takes focus.
struct PillButton: View {
    let title: String
    let prominent: Bool
    var large = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: large ? 17 : 12, weight: .semibold, design: .rounded))
                .padding(.horizontal, large ? 28 : 12)
                .padding(.vertical, large ? 12 : 5)
                .foregroundStyle(prominent ? Color.white : Color.primary)
                .background(prominent ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

@MainActor
final class NudgeController {
    private let model: WaterModel
    private let panel = FloatingPanel(title: "Sip Reminder")
    private var showing: Nudge?

    init(model: WaterModel) {
        self.model = model
        panel.level = .statusBar
        track()
    }

    private func track() {
        let nudge = withObservationTracking { model.isLocked ? nil : model.nudge } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
        apply(nudge)
    }

    private func apply(_ nudge: Nudge?) {
        guard nudge != showing else { return }
        showing = nudge
        guard let nudge, let screen = NSScreen.main ?? NSScreen.screens.first else {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; panel.animator().alphaValue = 0 }) { [weak self] in
                MainActor.assumeIsolated { if self?.showing == nil { self?.panel.orderOut(nil) } }
            }
            return
        }
        let host = FloatingHost(rootView: NudgeView(model: model, nudge: nudge))
        panel.contentView = host
        let size = host.fittingSize
        let area = screen.visibleFrame
        let frame = NSRect(x: area.maxX - size.width, y: area.maxY - size.height, width: size.width, height: size.height)
        panel.setFrame(frame.offsetBy(dx: 40, dy: 0), display: true)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
    }
}
