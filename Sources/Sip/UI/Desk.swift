import AppKit
import SwiftUI

/// A transparent, non-activating panel that floats above every Space without taking focus.
final class FloatingPanel: NSPanel {
    init(title: String) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        self.title = title
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes the first click even while Sip is in the background, and reports hover without needing focus.
final class FloatingHost<Content: View>: NSHostingView<Content> {
    var onHover: ((Bool) -> Void)?
    /// The part of the window that counts as hovering, in window coordinates; nil means all of it.
    var hoverRegion: (() -> NSRect?)?
    private var tracking: NSTrackingArea?
    private var inside = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        update(event, inWindow: true)
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        update(event, inWindow: true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        update(event, inWindow: false)
    }

    private func update(_ event: NSEvent, inWindow: Bool) {
        let now = inWindow && (hoverRegion?().map { $0.contains(event.locationInWindow) } ?? true)
        guard now != inside else { return }
        inside = now
        onHover?(now)
    }
}

/// Your bottle on the screen. The water shows how much you've had today.
struct DeskView: View {
    let model: WaterModel
    /// Called while the bottle is dragged (`false`) and when it's let go (`true`).
    var onDrag: (Bool) -> Void = { _ in }
    static let size = CGSize(width: 200, height: 236)

    private var late: Bool { model.phase == .due || model.phase == .overdue }
    /// A finished bottle's message shows for a moment even without hovering.
    private var showsDetails: Bool { model.deskHover || model.celebration != nil || model.deskIntro }
    private var collapsed: Bool { model.deskCollapsed && !showsDetails }
    /// A reminder shows on the bar itself, even with the bottle tucked away.
    private var reminder: String? { model.celebration == nil ? model.nudgeLine : nil }
    private var alignment: HorizontalAlignment { model.deskOnLeft ? .leading : .trailing }
    private var drag: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { _ in onDrag(false) }
            .onEnded { _ in onDrag(true) }
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            Spacer(minLength: 0)
            bottle
                .opacity(collapsed ? 0 : 1)
                .scaleEffect(collapsed ? 0.6 : 1, anchor: .bottom)
                .allowsHitTesting(!collapsed)
            details
        }
        .keyframeAnimator(initialValue: 0.0, trigger: model.wiggle) { content, angle in
            content.rotationEffect(.degrees(angle), anchor: .bottom)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-7, duration: 0.08)
                CubicKeyframe(7, duration: 0.12)
                CubicKeyframe(-5, duration: 0.12)
                CubicKeyframe(4, duration: 0.12)
                CubicKeyframe(-2, duration: 0.1)
                CubicKeyframe(0, duration: 0.1)
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: collapsed)
        .padding(.horizontal, 4)
        .frame(width: Self.size.width, height: Self.size.height, alignment: model.deskOnLeft ? .bottomLeading : .bottomTrailing)
    }

    private var bottle: some View {
            ZStack(alignment: .bottom) {
                BottleView(level: model.deskLevel, warning: late, sloshes: true)
                    .animation(.spring(duration: 0.9, bounce: 0.25), value: model.deskLevel)
                    .frame(height: 124)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                    .scaleEffect(model.deskHover ? 1.04 : 1, anchor: .bottom)
                    .contentShape(Rectangle())
                    .gesture(drag)
                    .help(Text("Drag to move the bottle"))
                if model.deskHover, model.current != nil {
                    Button {
                        model.finishBottle()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .foregroundStyle(.white)
                            .background(Color.accentColor, in: Capsule())
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 14)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .help(Text("I drank this bottle. Start the next one."))
                }
            }
            .frame(width: 90)
            .animation(.spring(duration: 0.3, bounce: 0.35), value: model.deskHover)
    }

    /// Caption and today's bottles. Collapsed, only the bottles show.
    private var details: some View {
        VStack(alignment: alignment, spacing: 2) {
            if let reminder, !model.deskHover {
                Text(reminder)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(late ? AnyShapeStyle(Color.orange) : AnyShapeStyle(Color.accentColor))
            } else if !collapsed {
                Text(model.deskCaption)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.celebration != nil ? AnyShapeStyle(Color.accentColor)
                                     : late ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.primary))
                if model.celebration == nil, !model.deskHint.isEmpty {
                    Text(model.deskHint)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 3) {
                ForEach(model.slots) { slot in
                    let current = slot.index == model.doneCount
                    Image(systemName: slot.index < model.doneCount ? "waterbottle.fill" : "waterbottle")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(slot.index < model.doneCount ? AnyShapeStyle(Color.accentColor)
                                         : current && late ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                }
            }
            .padding(.top, collapsed ? 0 : 2)
            .help(Text("\(model.doneCount) of \(model.plan.bottleCount) bottles today"))
        }
        .multilineTextAlignment(model.deskOnLeft ? .leading : .trailing)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .gesture(drag)
        .animation(.easeInOut(duration: 0.3), value: model.deskCaption)
        .animation(.easeInOut(duration: 0.25), value: reminder)
    }

    /// Where the collapsed row sits in the panel, in window coordinates, so only it wakes the bottle.
    static func collapsedRegion(bottles: Int, onLeft: Bool, withLine: Bool) -> NSRect {
        let width = withLine ? size.width : CGFloat(bottles) * 13 + 30
        return NSRect(x: onLeft ? 0 : size.width - width, y: 0, width: width, height: withLine ? 56 : 32)
    }
}

@MainActor
final class DeskController {
    private let model: WaterModel
    private let panel = FloatingPanel(title: "Sip Bottle")
    private var dragStart: (mouse: CGPoint, origin: CGPoint)?
    private var lastDrag: (point: CGPoint, time: TimeInterval, velocity: Double)?
    private var collapseTimer: Timer?
    private static let collapseAfter: TimeInterval = 5

    init(model: WaterModel) {
        self.model = model
        let host = FloatingHost(rootView: DeskView(model: model) { _ in })
        host.sizingOptions = []
        host.hoverRegion = { [weak model] in
            guard let model, model.deskCollapsed else { return nil }
            return DeskView.collapsedRegion(bottles: model.slots.count, onLeft: model.deskOnLeft, withLine: model.nudgeLine != nil)
        }
        host.onHover = { [weak self] inside in self?.hover(inside) }
        host.rootView = DeskView(model: model) { [weak self] ended in self?.drag(ended: ended) }
        panel.contentView = host
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        track()
        scheduleCollapse()
    }

    private func hover(_ inside: Bool) {
        model.deskHover = inside
        model.deskIntro = false
        if inside {
            collapseTimer?.invalidate()
            model.deskCollapsed = false
        } else {
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        collapseTimer?.invalidate()
        collapseTimer = Timer.scheduledTimer(withTimeInterval: Self.collapseAfter, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // Wait out a finished bottle's message, or a drag in progress.
                if self.model.deskHover || self.model.celebration != nil || self.dragStart != nil {
                    self.scheduleCollapse()
                } else {
                    self.model.deskIntro = false
                    self.model.deskCollapsed = true
                }
            }
        }
    }

    private func track() {
        let placement = withObservationTracking { (model.onScreen && !model.isLocked, model.corner) } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
        apply(visible: placement.0, corner: placement.1)
    }

    private func layout() { apply(visible: model.onScreen && !model.isLocked, corner: model.corner) }

    private func apply(visible: Bool, corner: Corner) {
        guard visible, let screen = NSScreen.main ?? NSScreen.screens.first else {
            panel.orderOut(nil)
            return
        }
        panel.setFrame(NSRect(origin: clamp(savedOrigin ?? defaultOrigin(corner, on: screen)), size: DeskView.size), display: true)
        updateSide()
        panel.orderFrontRegardless()
    }

    /// On the right, high enough to clear anything living in the bottom-right corner.
    private func defaultOrigin(_ corner: Corner, on screen: NSScreen) -> CGPoint {
        let area = screen.visibleFrame
        let size = DeskView.size
        return corner == .bottomLeft
            ? CGPoint(x: area.minX + 12, y: area.minY + 12)
            : CGPoint(x: area.maxX - size.width - 12, y: area.minY + 290)
    }

    private var savedOrigin: CGPoint? {
        guard let values = UserDefaults.standard.array(forKey: Prefs.deskOrigin) as? [Double], values.count == 2 else { return nil }
        return CGPoint(x: values[0], y: values[1])
    }

    /// Keeps the bottle on a screen that's still attached.
    private func clamp(_ origin: CGPoint) -> CGPoint {
        let size = DeskView.size
        let frame = NSRect(origin: origin, size: size)
        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(frame) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let area = screen?.visibleFrame else { return origin }
        return CGPoint(x: min(max(origin.x, area.minX - 40), area.maxX - size.width + 40),
                       y: min(max(origin.y, area.minY - 40), area.maxY - size.height))
    }

    private func updateSide() {
        let screen = panel.screen ?? NSScreen.main
        let onLeft = panel.frame.midX < (screen?.frame.midX ?? 0)
        if model.deskOnLeft != onLeft { model.deskOnLeft = onLeft }
    }

    private func drag(ended: Bool) {
        let mouse = NSEvent.mouseLocation
        if ended {
            dragStart = nil
            lastDrag = nil
            let origin = clamp(panel.frame.origin)
            panel.setFrameOrigin(origin)
            UserDefaults.standard.set([Double(origin.x), Double(origin.y)], forKey: Prefs.deskOrigin)
            updateSide()
            return
        }
        if dragStart == nil { dragStart = (mouse, panel.frame.origin) }
        guard let start = dragStart else { return }
        panel.setFrameOrigin(CGPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
        // Moving the bottle sideways makes the water lag behind, like carrying a real one.
        let now = ProcessInfo.processInfo.systemUptime
        if let last = lastDrag, now - last.time > 0.001 {
            let velocity = Double(mouse.x - last.point.x) / (now - last.time)
            Slosh.shared.kick((velocity - last.velocity) * 0.0009)
            lastDrag = (mouse, now, velocity)
        } else {
            lastDrag = (mouse, now, 0)
        }
    }
}
