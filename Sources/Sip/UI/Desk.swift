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

/// Your bottle, standing in a bottom corner of the screen. The water shows how much should be left right now.
struct DeskView: View {
    let model: WaterModel
    static let size = CGSize(width: 200, height: 236)

    private var late: Bool { model.phase == .due || model.phase == .overdue }
    private var alignment: HorizontalAlignment { model.corner == .bottomLeft ? .leading : .trailing }

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            Spacer(minLength: 0)
            ZStack(alignment: .bottom) {
                BottleView(level: model.deskLevel, warning: late)
                    .animation(.spring(duration: 0.9, bounce: 0.25), value: model.deskLevel)
                    .frame(height: 124)
                    .shadow(color: .black.opacity(0.28), radius: 8, y: 5)
                    .scaleEffect(model.deskHover ? 1.04 : 1, anchor: .bottom)
                if model.deskHover, model.current != nil {
                    Button {
                        model.finishBottle()
                    } label: {
                        Label("Finished", systemImage: "checkmark")
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
                    .help(Text("I finished this bottle. Start the next one."))
                }
            }
            .frame(width: 90)
            .animation(.spring(duration: 0.3, bounce: 0.35), value: model.deskHover)

            VStack(alignment: alignment, spacing: 2) {
                Text(model.deskCaption)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.celebration != nil ? AnyShapeStyle(Color.accentColor)
                                     : late ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.primary))
                if model.deskHover, model.celebration == nil, !model.deskHint.isEmpty {
                    Text(model.deskHint)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                HStack(spacing: 3) {
                    ForEach(model.slots) { slot in
                        Image(systemName: slot.index < model.doneCount ? "waterbottle.fill" : "waterbottle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(slot.index < model.doneCount ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    }
                }
                .padding(.top, 2)
                .help(Text("\(model.doneCount) of \(model.plan.bottleCount) bottles today"))
            }
            .multilineTextAlignment(model.corner == .bottomLeft ? .leading : .trailing)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .animation(.easeInOut(duration: 0.25), value: model.deskHover)
            .animation(.easeInOut(duration: 0.3), value: model.deskCaption)
        }
        .padding(.horizontal, 4)
        .frame(width: Self.size.width, height: Self.size.height, alignment: model.corner == .bottomLeft ? .bottomLeading : .bottomTrailing)
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
            MainActor.assumeIsolated { self?.layout() }
        }
        track()
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
        let area = screen.visibleFrame
        let size = DeskView.size
        let x = corner == .bottomLeft ? area.minX + 12 : area.maxX - size.width - 12
        panel.setFrame(NSRect(x: x, y: area.minY + 12, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
    }
}

