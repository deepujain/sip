#if DEBUG
import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders the main states to PNGs for visual review: `Sip --snapshots <dir>`.
@MainActor
enum Snapshots {
    static func render(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        BottleView.drawsStill = true
        let model = WaterModel()
        let slots = model.plan.slots(on: .now)
        let midday = slots[1].start.addingTimeInterval(slots[1].duration * 0.4)

        model.stage(now: midday, done: 1)
        try write(desk(model), to: folder.appending(path: "2-desk-intro.png"))
        model.deskIntro = false
        try write(menu(model), to: folder.appending(path: "1-menu.png"))
        try write(desk(model), to: folder.appending(path: "2-desk.png"))
        model.deskHover = true
        try write(desk(model), to: folder.appending(path: "2-desk-hover.png"))
        model.deskHover = false
        model.deskCollapsed = true
        try write(desk(model), to: folder.appending(path: "2-desk-collapsed.png"))
        model.deskCollapsed = false

        let due = slots[1].end.addingTimeInterval(120)
        model.stage(now: due, done: 1, nudge: .due(slots[1]))
        try write(menu(model), to: folder.appending(path: "3-menu-due.png"))
        model.deskCollapsed = true
        try write(desk(model), to: folder.appending(path: "4-nudge-due.png"))
        let half = slots[1].start.addingTimeInterval(slots[1].duration * 0.5)
        model.stage(now: half, done: 1, nudge: .halfway(slots[1]))
        try write(desk(model), to: folder.appending(path: "4-nudge-halfway.png"))
        model.deskCollapsed = false

        model.stage(now: due.addingTimeInterval(700), done: 1, locked: true)
        try write(AnyView(LockView(model: model, primary: true).frame(width: 1280, height: 800).background(wallpaper)),
                  to: folder.appending(path: "5-lock.png"))

        model.stage(now: slots[2].start.addingTimeInterval(60), done: 2,
                    celebration: "Bottle 2 done · \(Benefit.pick(at: slots[2].start, bottle: 1).short)")
        try write(desk(model), to: folder.appending(path: "2-desk-done.png"))

        model.stage(now: slots[3].end.addingTimeInterval(600), done: 4, streak: 7)
        try write(menu(model), to: folder.appending(path: "6-menu-done.png"))

        try write(AnyView(WelcomeView {}.background(Color(nsColor: .windowBackgroundColor))), to: folder.appending(path: "7-welcome.png"))
        try write(AnyView(SettingsView(model: model).background(Color(nsColor: .windowBackgroundColor))), to: folder.appending(path: "8-settings.png"))
        try write(AnyView(AppIconArtwork().scaleEffect(0.25).frame(width: 256, height: 256)), to: folder.appending(path: "9-icon.png"))

        BottleView.drawsStill = false
        model.stage(now: due, done: 1, nudge: .due(slots[1]))
        try live(AnyView(DeskView(model: model).padding(30).background(Color(white: 0.95))), to: folder.appending(path: "live-desk.png"))
        model.stage(now: slots[2].start.addingTimeInterval(60), done: 2,
                    celebration: "Bottle 2 done · \(Benefit.pick(at: slots[2].start, bottle: 1).short)")
        try live(AnyView(DeskView(model: model).padding(30).background(Color(white: 0.95))), to: folder.appending(path: "live-desk-done.png"))
        model.stage(now: slots[2].start.addingTimeInterval(60), done: 2)
        for (name, roll) in [("live-tilt-right-up", 0.35), ("live-tilt-left-up", -0.35)] {
            Slosh.shared.settle(roll: roll)
            try live(AnyView(DeskView(model: model).padding(30).background(Color(white: 0.95))), to: folder.appending(path: "\(name).png"))
        }
        Slosh.shared.settle(roll: 0)
        try live(AnyView(BenefitsView().background(Color(nsColor: .windowBackgroundColor))), to: folder.appending(path: "live-benefits.png"))
        try live(AnyView(AboutView().background(Color(nsColor: .windowBackgroundColor))), to: folder.appending(path: "live-about.png"))
        BottleView.drawsStill = true
        model.stage(now: due.addingTimeInterval(700), done: 1, locked: true)
        try live(AnyView(LockView(model: model, primary: true).frame(width: 1280, height: 860)), to: folder.appending(path: "live-lock.png"))
    }

    /// Draws through a real window, the way the app shows it, instead of `ImageRenderer`.
    private static func live(_ view: AnyView, to url: URL) throws {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -4000, y: -4000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
        window.orderOut(nil)
    }

    private static var wallpaper: some View {
        LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.82, green: 0.6, blue: 0.55)],
                       startPoint: .top, endPoint: .bottom)
    }

    private static func menu(_ model: WaterModel) -> AnyView {
        AnyView(MenuContent(model: model, showWelcome: {}, showBenefits: {}).background(.regularMaterial))
    }

    private static func desk(_ model: WaterModel) -> AnyView {
        AnyView(DeskView(model: model).padding(30).background(wallpaper))
    }

    private static func write(_ view: AnyView, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
}
#endif
