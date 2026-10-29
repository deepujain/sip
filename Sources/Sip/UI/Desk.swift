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
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}

/// Your bottle, standing in the bottom-right corner of the screen and draining on schedule.
struct DeskView: View {
    let model: WaterModel
    static let size = CGSize(width: 190, height: 268)

    private var late: Bool { model.phase == .due || model.phase == .overdue }

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                BottleView(level: model.deskLevel, warning: late)
                    .animation(.spring(duration: 0.9, bounce: 0.25), value: model.deskLevel)
                    .frame(height: 176)
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 6)
                    .scaleEffect(model.deskHover ? 1.04 : 1, anchor: .bottom)
                if model.deskHover, model.current != nil {
                    Button {
                        model.finishBottle()
                    } label: {
                        Label("Empty", systemImage: "checkmark")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(.white)
                            .background(Color.accentColor, in: Capsule())
                            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 22)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .help(Text("Mark this bottle empty and start the next one"))
                }
            }
            .animation(.spring(duration: 0.3, bounce: 0.35), value: model.deskHover)

            Text(model.deskCaption)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(model.celebration != nil ? AnyShapeStyle(Color.accentColor)
                                 : late ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.primary))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .frame(maxWidth: Self.size.width - 10)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: model.deskCaption)

            HStack(spacing: 3) {
                ForEach(model.slots) { slot in
                    Image(systemName: slot.index < model.doneCount ? "waterbottle.fill" : "waterbottle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(slot.index < model.doneCount ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .help(Text("\(model.doneCount) of \(model.plan.bottleCount) bottles today"))
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

@MainActor
final class DeskController {
    private let model: WaterModel
    private let panel = FloatingPanel(title: "Sip Bottle")

    init(model: WaterModel) {
        self.model = model
        let host = FloatingHost(rootView: DeskView(model: model))
        host.sizingOptions = []
        host.onHover = { [weak model] inside in model?.deskHover = inside }
        panel.contentView = host
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply(visible: self?.visible ?? false) }
        }
        track()
    }

    private var visible: Bool { model.onScreen && !model.isLocked }

    private func track() {
        let show = withObservationTracking { visible } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
        apply(visible: show)
    }

    private func apply(visible: Bool) {
        guard visible, let screen = NSScreen.main ?? NSScreen.screens.first else {
            panel.orderOut(nil)
            return
        }
        let area = screen.visibleFrame
        let size = DeskView.size
        panel.setFrame(NSRect(x: area.maxX - size.width - 12, y: area.minY + 12, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }
}
