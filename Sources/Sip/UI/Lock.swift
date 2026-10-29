import AppKit
import SwiftUI

/// The Dry Spell: every display goes behind frosted glass until the bottle is empty or the time runs out.
struct LockView: View {
    let model: WaterModel
    let primary: Bool

    var body: some View {
        ZStack {
            if BottleView.drawsStill {
                Color(red: 0.16, green: 0.2, blue: 0.3)
            } else {
                Blur()
            }
            Color.black.opacity(0.38)
            if primary { content }
        }
        .ignoresSafeArea()
    }

    private var title: String {
        if model.previewLock { return "This is a Dry Spell" }
        return model.current.map { "Time to finish bottle \($0.number)" } ?? "Time for water"
    }

    private var content: some View {
        VStack(spacing: 26) {
            BottleView(level: model.previewLock ? 0.3 : 0.06, warning: true)
                .frame(height: 300)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(model.previewLock
                     ? "When a bottle is still full past its time, your Mac takes a short water break like this one."
                     : "Your Mac is taking a water break. It unlocks when the bottle is empty.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }
            let benefit = model.lockBenefit
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: benefit.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(benefit.fact)
                        .font(.system(size: 15, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(benefit.source)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 520, alignment: .leading)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Countdown(model: model)
            PillButton(title: model.previewLock ? "Got it" : "Bottle’s empty", prominent: true, large: true) {
                model.finishBottle()
            }
            .keyboardShortcut(.return)
            EmergencyHold { model.endLock(finished: false) }
                .padding(.top, 6)
        }
        .foregroundStyle(.white)
        .padding(40)
    }
}

private struct Countdown: View {
    let model: WaterModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let date = BottleView.drawsStill ? model.now : context.date
            let total = max(1, (model.lockedUntil ?? date).timeIntervalSince(model.lockStarted ?? date))
            let left = max(0, (model.lockedUntil ?? date).timeIntervalSince(date))
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: left / total)
                    .stroke(.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: left)
                VStack(spacing: 0) {
                    Text(Fmt.countdown(left))
                        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                    Text("left")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .frame(width: 96, height: 96)
        }
    }
}

/// Always a way out: hold for three seconds. The bottle comes back later if it's still full.
private struct EmergencyHold: View {
    let action: () -> Void
    private let progressState = State(initialValue: 0.0)

    private var progress: Double {
        get { progressState.wrappedValue }
        nonmutating set { progressState.wrappedValue = newValue }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(progress > 0 ? "Keep holding…" : "Hold here for an emergency unlock")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
            Capsule()
                .fill(.white.opacity(0.15))
                .frame(width: 180, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.85)).frame(width: 180 * progress, height: 4)
                }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 3, maximumDistance: 40) {
            progress = 0
            action()
        } onPressingChanged: { pressing in
            withAnimation(pressing ? .linear(duration: 3) : .easeOut(duration: 0.2)) { progress = pressing ? 1 : 0 }
        }
    }
}

private struct Blur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private final class LockWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
        title = "Sip Dry Spell"
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class LockController {
    private let model: WaterModel
    private var windows: [NSWindow] = []
    private var resignObserver: NSObjectProtocol?

    init(model: WaterModel) {
        self.model = model
        track()
    }

    private func track() {
        let locked = withObservationTracking { model.isLocked } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
        locked ? lock() : unlock()
    }

    private func lock() {
        guard windows.isEmpty else { return }
        let main = NSScreen.main ?? NSScreen.screens.first
        for screen in NSScreen.screens {
            let window = LockWindow(screen: screen)
            window.contentView = NSHostingView(rootView: LockView(model: model, primary: screen == main))
            window.setFrame(screen.frame, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        windows.first { $0.screen == main }?.makeKeyAndOrderFront(nil)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            windows.forEach { $0.animator().alphaValue = 1 }
        }
        // Cmd-Tab is off, but a click on another display or a notification could still pull focus away.
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.windows.isEmpty else { return }
                NSApp.activate(ignoringOtherApps: true)
                self.windows.forEach { $0.orderFrontRegardless() }
            }
        }
    }

    private func unlock() {
        guard !windows.isEmpty else { return }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        NSApp.presentationOptions = []
        let closing = windows
        windows = []
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.45
            closing.forEach { $0.animator().alphaValue = 0 }
        }) {
            MainActor.assumeIsolated { closing.forEach { $0.close() } }
        }
    }
}
