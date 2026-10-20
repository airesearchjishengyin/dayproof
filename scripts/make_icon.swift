import AppKit
import SwiftUI

struct AppIconArtwork: View {
    var body: some View {
        ZStack {
            Color(red: 0.28, green: 0.43, blue: 0.35)
            CatDrawing(blink: false, happy: false)
                .frame(width: 850, height: 850)
        }
        .frame(width: 1024, height: 1024)
    }
}

@main
struct MakeIcon {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "DayproofIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Usage: make_icon.swift <iconset directory>"])
        }
        let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        let canvas = NSHostingView(rootView: AppIconArtwork())
        canvas.frame = NSRect(x: 0, y: 0, width: 1024, height: 1024)
        guard let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else {
            throw NSError(domain: "DayproofIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not allocate icon bitmap"])
        }
        canvas.cacheDisplay(in: canvas.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "DayproofIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG"])
        }
        let sizes: [(Int, String, Int)] = [
            (16, "icon_16x16.png", 1), (16, "icon_16x16@2x.png", 2),
            (32, "icon_32x32.png", 1), (32, "icon_32x32@2x.png", 2),
            (128, "icon_128x128.png", 1), (128, "icon_128x128@2x.png", 2),
            (256, "icon_256x256.png", 1), (256, "icon_256x256@2x.png", 2),
            (512, "icon_512x512.png", 1), (512, "icon_512x512@2x.png", 2),
        ]
        guard let source = NSImage(data: png) else { throw NSError(domain: "DayproofIcon", code: 4) }
        for (points, name, scale) in sizes {
            let pixels = points * scale
            let image = NSImage(size: NSSize(width: pixels, height: pixels))
            image.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: NSRect(x: 0, y: 0, width: 1024, height: 1024), operation: .copy, fraction: 1)
            image.unlockFocus()
            guard let output = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: output),
                  let result = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "DayproofIcon", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not resize \(name)"])
            }
            try result.write(to: iconset.appendingPathComponent(name))
        }
    }
}
