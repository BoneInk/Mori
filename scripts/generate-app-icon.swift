#!/usr/bin/env swift

import AppKit
import Foundation

private let fileManager = FileManager.default
private let projectDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
private let resourcesDirectory = projectDirectory.appendingPathComponent("Resources", isDirectory: true)
private let iconsetDirectory = resourcesDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)

private func color(_ hex: UInt32) -> NSColor {
    NSColor(
        red: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: 1
    )
}

private func renderIcon(pixelSize: Int) throws -> Data {
    let size = CGFloat(pixelSize)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "MirrorIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not allocate icon bitmap."])
    }

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "MirrorIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create graphics context."])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.cgContext.setShouldAntialias(true)

    // Match the compact brand mark used in Mirror's title bar: a warm paper
    // tile, a restrained outline, and the orange Xingkai “觅” glyph.
    let inset = size * 0.085
    let tileRect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = tileRect.width * (8.0 / 29.0)
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)
    color(0xEEE4CF).setFill()
    tile.fill()

    color(0xDFD1B6).setStroke()
    tile.lineWidth = max(1, tileRect.width / 29)
    tile.stroke()

    let fontSize = tileRect.width * (19.0 / 29.0)
    let font = NSFont(name: "STXingkaiSC-Light", size: fontSize)
        ?? NSFont(name: "STKaitiSC-Regular", size: fontSize)
        ?? NSFont.systemFont(ofSize: fontSize, weight: .regular)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color(0xC56B32)
    ]
    let glyph = NSAttributedString(string: "觅", attributes: attributes)
    let bounds = glyph.boundingRect(
        with: CGSize(width: size, height: size),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let drawPoint = CGPoint(
        x: tileRect.midX - bounds.width / 2 - bounds.minX,
        y: tileRect.midY - bounds.height / 2 - bounds.minY
    )
    glyph.draw(at: drawPoint)

    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MirrorIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode icon PNG."])
    }
    return data
}

private let iconFiles: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

try? fileManager.removeItem(at: iconsetDirectory)
try fileManager.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)

for iconFile in iconFiles {
    let data = try renderIcon(pixelSize: iconFile.pixels)
    try data.write(to: iconsetDirectory.appendingPathComponent(iconFile.name), options: .atomic)
}

try renderIcon(pixelSize: 1024).write(
    to: resourcesDirectory.appendingPathComponent("AppIcon.png"),
    options: .atomic
)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "--convert", "icns",
    "--output", resourcesDirectory.appendingPathComponent("AppIcon.icns").path,
    iconsetDirectory.path
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    throw NSError(domain: "MirrorIcon", code: 4, userInfo: [NSLocalizedDescriptionKey: "iconutil failed."])
}

try fileManager.removeItem(at: iconsetDirectory)
print(resourcesDirectory.appendingPathComponent("AppIcon.icns").path)
