import AppKit
import os
import SwiftUI

/// The Dry Spell: every display goes behind a clear blue tint, like looking through water, with one glass
/// card in the middle, until the bottle is empty or the time runs out.
struct LockView: View {
    let model: WaterModel
    let primary: Bool
    #if DEBUG
    /// A still photo behind the glass, for the website images.
    static var backdrop: AnyView?
    #endif

    /// The card's natural size; smaller screens scale it down so nothing is ever cut off.
    private static let card = CGSize(width: 860, height: 500)

    var body: some View {
        ZStack {
            #if DEBUG
            Self.backdrop
            #endif
            LinearGradient(colors: [Color(red: 0.05, green: 0.2, blue: 0.4).opacity(0.18),
                                    Color(red: 0.05, green: 0.25, blue: 0.5).opacity(0.42)],
                           startPoint: .top, endPoint: .bottom)
            if primary {
                GeometryReader { space in
                    let scale = min(1, (space.size.width - 48) / Self.card.width, (space.size.height - 48) / Self.card.height)
                    content
                        .scaleEffect(scale)
                        .frame(width: space.size.width, height: space.size.height)
                }
            }
        }
        .ignoresSafeArea()
    }

    private var title: String {
        if model.previewLock { return "This is a Dry Spell" }
        return model.current.map { "Time to finish bottle \($0.number)" } ?? "Time for water"
    }

    private var content: some View {
        HStack(spacing: 48) {
            CapUnlock(level: model.previewLock ? 0.3 : 0.06, sounds: model.sounds) { model.endLock(finished: false, emergency: true) }
                .frame(height: 360)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(model.previewLock
                         ? "When a bottle is still full past its time, your Mac takes a short water break like this one."
                         : "Your Mac is taking a water break. It unlocks when the bottle is empty.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.8))
                }
                .fixedSize(horizontal: false, vertical: true)
                benefit
                HStack(spacing: 22) {
                    Countdown(model: model)
                    PillButton(title: model.previewLock ? "Got it" : "Bottle’s empty", prominent: true, large: true) {
                        model.finishBottle()
                    }
                    .keyboardShortcut(.return)
                }
                if model.unlockCode != nil {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.fill")
                        Text("Or type the unlock code")
                        CodeBoxes(entry: model.codeEntry)
                            .modifier(Shake(misses: model.codeMisses))
                            .animation(.linear(duration: 0.4), value: model.codeMisses)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(width: 470, alignment: .leading)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 48)
        .padding(.vertical, 40)
        .frame(width: Self.card.width, height: Self.card.height)
        .modifier(GlassCard())
    }

    private var benefit: some View {
        let benefit = model.lockBenefit
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: benefit.symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(benefit.fact)
                    .font(.system(size: 15, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(benefit.source)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Two boxes that fill with a dot for each digit typed.
private struct CodeBoxes: View {
    let entry: String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { index in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.12))
                    .strokeBorder(.white.opacity(index == entry.count ? 0.8 : 0.35), lineWidth: 1.5)
                    .overlay {
                        if index < entry.count { Circle().fill(.white).frame(width: 9, height: 9) }
                    }
                    .frame(width: 32, height: 38)
            }
        }
    }
}

/// A quick side-to-side shake after a wrong code.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat

    init(misses: Int) { animatableData = CGFloat(misses) }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 6), y: 0))
    }
}

/// Liquid Glass with a deep blue tint, so the screen behind shows through and white text stays readable.
private struct GlassCard: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
    private let tint = Color(red: 0.03, green: 0.12, blue: 0.26)

    func body(content: Content) -> some View {
        if BottleView.drawsStill {
            // Image rendering can't draw glass or materials.
            content
                .background(tint.opacity(0.55), in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.25)))
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular.tint(tint.opacity(0.55)), in: shape)
        } else {
            content
                .background(tint.opacity(0.6), in: shape)
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(.white.opacity(0.2)))
        }
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

/// Always a way out, even past a parent's code, though the lock screen never mentions it: hold the
/// bottle's cap and it unscrews, rising a little with each turn, until it pops off after three seconds
/// and the screen unlocks. Let go early and it screws itself back down. That bottle won't lock the Mac again.
struct CapUnlock: View {
    let level: Double
    let sounds: Bool
    let action: () -> Void
    private static let holdTime = 3.0
    private static let settleTime = 0.3

    private struct Hold { var pressed: Date?; var released: (at: Date, from: Double)?; var popped = false }
    private let holdState = State(initialValue: Hold())
    private var hold: Hold {
        get { holdState.wrappedValue }
        nonmutating set { holdState.wrappedValue = newValue }
    }

    #if DEBUG
    nonisolated(unsafe) static var previewTurn: Double?
    #endif

    private func turn(at date: Date) -> Double {
        #if DEBUG
        if let turn = Self.previewTurn { return turn }
        #endif
        if hold.popped { return 1 }
        if let pressed = hold.pressed { return min(1, date.timeIntervalSince(pressed) / Self.holdTime) }
        if let released = hold.released { return max(0, released.from * (1 - date.timeIntervalSince(released.at) / Self.settleTime)) }
        return 0
    }

    var body: some View {
        TimelineView(.animation(paused: hold.pressed == nil && hold.released == nil)) { context in
            let turn = turn(at: context.date)
            ZStack {
                BottleView(level: level, cap: .off)
                BottleView(level: level, animated: false, capTurn: turn, cap: .alone)
                    // It climbs the thread for the whole hold, staying seated on the glass, and comes free right at the end.
                    .visualEffect { content, proxy in
                        content.offset(y: -CGFloat(turn) * proxy.size.height * BottleView.threadLength)
                    }
                    .rotationEffect(.degrees(hold.popped ? -40 : sin(turn * 40) * 1.2 * turn), anchor: .top)
                    .offset(x: hold.popped ? -30 : 0, y: hold.popped ? -110 : 0)
                    .opacity(hold.popped ? 0 : 1)
                    .animation(.easeOut(duration: 0.5), value: hold.popped)
            }
            .overlay(alignment: .top) { grip }
        }
    }

    private var grip: some View {
        GeometryReader { space in
            Color.clear
                .contentShape(Rectangle())
                .frame(width: space.size.width * 0.75, height: space.size.height * 0.2)
                .frame(maxWidth: .infinity)
                .offset(y: -space.size.height * 0.05)
                .onLongPressGesture(minimumDuration: Self.holdTime, maximumDistance: 60) {
                    hold = Hold(popped: true)
                    if sounds { NSSound(named: "Pop")?.play() }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { action() }
                } onPressingChanged: { pressing in
                    guard !hold.popped else { return }
                    if pressing {
                        hold = Hold(pressed: Date())
                    } else {
                        let from = turn(at: Date())
                        hold = Hold(released: (Date(), from))
                        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleTime) {
                            if hold.pressed == nil && !hold.popped { hold = Hold() }
                        }
                    }
                }
        }
    }
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

/// Answers the very first click, even if macOS hasn't brought Sip to the front, so the way out always works.
private final class LockHost<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// If Sip ever freezes while the screen is covered, nothing inside it can lift the cover, so a separate
/// thread quits the app instead. When the process ends, macOS removes its windows from every screen.
final class LockWatchdog: @unchecked Sendable {
    private let beat = OSAllocatedUnfairLock(initialState: Date())
    private let armed = OSAllocatedUnfairLock(initialState: false)
    private let queue = DispatchQueue(label: "app.sip.lock-watchdog")
    private var source: DispatchSourceTimer?
    private let limit: TimeInterval

    init(limit: TimeInterval = 20) {
        self.limit = limit
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 2, repeating: 2)
        source.setEventHandler { [weak self] in self?.check() }
        source.resume()
        self.source = source
    }

    /// Called from the main thread while it's healthy.
    func heartbeat() { beat.withLock { $0 = Date() } }

    func arm(_ on: Bool) {
        heartbeat()
        armed.withLock { $0 = on }
    }

    private var lastCheck = Date()

    private func check() {
        let now = Date()
        defer { lastCheck = now }
        guard armed.withLock({ $0 }) else { return }
        // A long gap between checks means the Mac was asleep, not that Sip froze; give it a fresh start.
        if now.timeIntervalSince(lastCheck) > 6 { return heartbeat() }
        if now.timeIntervalSince(beat.withLock { $0 }) > limit { _exit(3) }
    }
}

@MainActor
final class LockController {
    private let model: WaterModel
    private var windows: [NSWindow] = []
    private var resignObserver: NSObjectProtocol?
    /// Ends the lock on time even if the model's clock stalls; runs in every run loop mode.
    private var deadline: Timer?
    private var pulse: Timer?
    private var keys: Any?
    private var escapes: [Date] = []
    private let watchdog = LockWatchdog()

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
        // Every display gets the buttons, so the way out is wherever you're looking.
        for screen in NSScreen.screens {
            let window = LockWindow(screen: screen)
            window.contentView = LockHost(rootView: LockView(model: model, primary: true))
            window.setFrame(screen.frame, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()
            windows.append(window)
        }
        NSApp.activate()
        windows.first { $0.screen == main }?.makeKeyAndOrderFront(nil)
        if let until = model.lockedUntil {
            let timer = Timer(fire: until.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.model.isLocked else { return }
                    self.model.endLock(finished: false)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            deadline = timer
        }
        let watchdog = watchdog
        let pulse = Timer(timeInterval: 1, repeats: true) { _ in watchdog.heartbeat() }
        RunLoop.main.add(pulse, forMode: .common)
        self.pulse = pulse
        watchdog.arm(true)
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            switch event.keyCode {
            case 53:
                MainActor.assumeIsolated { self?.escapePressed() }
            case 51, 117:
                MainActor.assumeIsolated { self?.model.eraseCode() }
            default:
                guard let digit = event.charactersIgnoringModifiers?.first, digit.isASCII, digit.isNumber,
                      event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return event }
                MainActor.assumeIsolated { self?.model.typeCode(digit) }
            }
            return nil
        }
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication]
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            windows.forEach { $0.animator().alphaValue = 1 }
        }
        // Cmd-Tab is off, but a click on another display or a notification could still pull focus away.
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.windows.isEmpty else { return }
                NSApp.activate()
                self.windows.forEach { $0.orderFrontRegardless() }
            }
        }
    }

    private func escapePressed() {
        let now = Date()
        escapes = escapes.filter { now.timeIntervalSince($0) < 2 } + [now]
        guard escapes.count >= 3 else { return }
        escapes = []
        model.endLock(finished: false, emergency: true)
    }

    private func unlock() {
        guard !windows.isEmpty else { return }
        deadline?.invalidate()
        deadline = nil
        watchdog.arm(false)
        pulse?.invalidate()
        pulse = nil
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
        escapes = []
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
