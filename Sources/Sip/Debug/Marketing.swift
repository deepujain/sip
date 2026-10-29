#if DEBUG
import AppKit
import SwiftUI

/// `Sip --marketing <folder>` renders the website images: the real views staged over the photos in `docs/photos`.
@MainActor
enum Marketing {
    static func render(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        output = folder
        BottleView.drawsStill = true
        let model = WaterModel()
        let slots = model.plan.slots(on: .now)

        // Late morning, one bottle down, hovering over the second.
        model.stage(now: slots[1].start.addingTimeInterval(slots[1].duration * 0.4), done: 1)
        model.deskIntro = false
        model.deskHover = true
        write(Poster(model: model), name: "sip-poster", size: CGSize(width: 1280, height: 800))
        write(Stage(photo: .midday, alignment: .bottomTrailing) { DeskView(model: model).scaleEffect(1.5, anchor: .bottomTrailing) },
              name: "shot-drink", size: CGSize(width: 800, height: 600))
        write(Stage(photo: .detail, alignment: .center) { panel(model) }, name: "shot-menu", size: CGSize(width: 560, height: 640))

        model.stage(now: slots[2].start.addingTimeInterval(60), done: 2,
                    celebration: "Bottle 2 done · \(Benefit.pick(at: slots[2].start, bottle: 1).short)")
        model.deskHover = false
        write(Stage(photo: .hero, alignment: .bottomTrailing) { DeskView(model: model).scaleEffect(1.5, anchor: .bottomTrailing) },
              name: "shot-done", size: CGSize(width: 800, height: 600))

        write(Stage(photo: .detail) { window(WelcomeView {}).scaleEffect(0.62) }, name: "shot-plan", size: CGSize(width: 800, height: 600))
        write(Stage(photo: .detail) { window(BenefitsView()).scaleEffect(0.7) }, name: "shot-benefits", size: CGSize(width: 800, height: 600))

        let due = slots[1].end.addingTimeInterval(120)
        model.stage(now: due, done: 1, nudge: .due(slots[1]))
        model.deskCollapsed = false
        write(Stage(photo: .afternoon, alignment: .bottomTrailing) { DeskView(model: model).scaleEffect(1.5, anchor: .bottomTrailing) },
              name: "shot-nudge", size: CGSize(width: 800, height: 600))

        model.stage(now: due.addingTimeInterval(700), done: 1, locked: true)
        LockView.backdrop = AnyView(Backdrop(photo: .afternoon).blur(radius: 28).scaleEffect(1.08))
        write(LockView(model: model, primary: true), name: "shot-lock", size: CGSize(width: 1280, height: 800))
        LockView.backdrop = nil
    }

    private static func panel(_ model: WaterModel) -> some View {
        MenuContent(model: model, showWelcome: {}, showBenefits: {})
            .background(Color(white: 0.97))
            .environment(\.colorScheme, .light)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.black.opacity(0.08), lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 26, y: 14)
    }

    private static func window(_ content: some View) -> some View {
        content
            .background(Color(white: 0.97))
            .environment(\.colorScheme, .light)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.3), radius: 30, y: 16)
    }

    private static func write(_ view: some View, name: String, size: CGSize?, scale: CGFloat = 2) {
        let renderer = ImageRenderer(content: view.frame(width: size?.width, height: size?.height))
        renderer.scale = scale
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: output.appending(path: "\(name).png"))
    }

    private static var output = URL(fileURLWithPath: ".")
}

private enum Photo: String {
    case hero, midday, afternoon, detail

    var image: Image {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: "docs/photos/\(rawValue).jpg")
        return NSImage(contentsOf: url).map { Image(nsImage: $0) } ?? Image(systemName: "drop")
    }
}

/// A photograph filling the frame behind the real UI.
private struct Backdrop: View {
    let photo: Photo

    var body: some View {
        Color.white.overlay { photo.image.resizable().interpolation(.high).scaledToFill() }.clipped()
    }
}

private struct Stage<Content: View>: View {
    let photo: Photo
    var alignment: Alignment = .center
    @ViewBuilder let content: Content

    var body: some View {
        ZStack(alignment: alignment) {
            Backdrop(photo: photo)
            content.padding(40)
        }
    }
}

/// A morning desktop: Sip's drop in the menu bar with its panel open, and the bottle in the corner.
private struct Poster: View {
    let model: WaterModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Backdrop(photo: .hero)
            menuBar
            MenuContent(model: model, showWelcome: {}, showBenefits: {})
                .background(Color(white: 0.97))
                .environment(\.colorScheme, .light)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 26, y: 14)
                .scaleEffect(0.92, anchor: .topTrailing)
                .padding(.top, 34)
                .padding(.trailing, 128)
            DeskView(model: model)
                .scaleEffect(1.25, anchor: .bottomTrailing)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 48)
                .padding(.bottom, 72)
        }
        .frame(width: 1280, height: 800)
        .clipped()
    }

    private var menuBar: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo")
            Text(verbatim: "Finder").fontWeight(.bold)
            ForEach(["File", "Edit", "View", "Go", "Window"], id: \.self) { Text(verbatim: $0) }
            Spacer()
            Image(systemName: model.menuSymbol)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.12)))
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Text(verbatim: model.now.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
        }
        .font(.system(size: 13))
        .foregroundStyle(.black.opacity(0.85))
        .padding(.horizontal, 18)
        .frame(height: 28)
        .background(Color.white.opacity(0.45))
    }
}
#endif
