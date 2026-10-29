import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Renders the app icon artwork into an `.iconset` folder for `iconutil`.
@MainActor
enum AppIconRenderer {
    static func writeIconset(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let renderer = ImageRenderer(content: AppIconArtwork())
        renderer.scale = 1
        guard let master = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let sizes: [(String, Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for (name, pixels) in sizes {
            guard let image = resize(master, to: pixels),
                  let destination = CGImageDestinationCreateWithURL(folder.appending(path: "\(name).png") as CFURL,
                                                                    UTType.png.identifier as CFString, 1, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }

    private static func resize(_ image: CGImage, to pixels: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }
}

struct AppIconArtwork: View {
    private let shape = RoundedRectangle(cornerRadius: 186, style: .continuous)

    var body: some View {
        ZStack {
            shape
                .fill(LinearGradient(colors: [Color(red: 0.62, green: 0.9, blue: 1), Color(red: 0.2, green: 0.56, blue: 1),
                                              Color(red: 0.1, green: 0.3, blue: 0.82)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.18))
                            .frame(width: 560, height: 560)
                            .offset(y: 40)
                        BottleView(level: 0.6, animated: false)
                            .frame(height: 640)
                            .shadow(color: .black.opacity(0.3), radius: 30, y: 18)
                            .offset(y: 20)
                    }
                    .frame(width: 824, height: 824)
                    .clipShape(shape)
                }
                .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 3))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 22, y: 12)
        }
        .frame(width: 1024, height: 1024)
    }
}
