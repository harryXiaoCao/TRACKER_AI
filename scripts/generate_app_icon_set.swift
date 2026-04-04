#!/usr/bin/env swift

import AppKit
import Foundation

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputDirectory = projectRoot
    .appendingPathComponent("macos/TrackerAI/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

let iconSizes = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func makeBitmap(size: Int, draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func drawBaseIcon(size: Int) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    rect.fill()

    let roundedRect = NSBezierPath(roundedRect: rect.insetBy(dx: CGFloat(size) * 0.06, dy: CGFloat(size) * 0.06),
                                   xRadius: CGFloat(size) * 0.22,
                                   yRadius: CGFloat(size) * 0.22)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.07, green: 0.15, blue: 0.30, alpha: 1),
        NSColor(calibratedRed: 0.06, green: 0.44, blue: 0.66, alpha: 1),
        NSColor(calibratedRed: 0.13, green: 0.74, blue: 0.73, alpha: 1),
    ])!
    gradient.draw(in: roundedRect, angle: 315)

    NSColor.white.withAlphaComponent(0.16).setFill()
    let flare = NSBezierPath()
    flare.move(to: CGPoint(x: CGFloat(size) * 0.20, y: CGFloat(size) * 0.78))
    flare.curve(to: CGPoint(x: CGFloat(size) * 0.83, y: CGFloat(size) * 0.96),
                controlPoint1: CGPoint(x: CGFloat(size) * 0.42, y: CGFloat(size) * 0.98),
                controlPoint2: CGPoint(x: CGFloat(size) * 0.61, y: CGFloat(size) * 0.98))
    flare.line(to: CGPoint(x: CGFloat(size) * 0.83, y: CGFloat(size) * 0.82))
    flare.curve(to: CGPoint(x: CGFloat(size) * 0.28, y: CGFloat(size) * 0.62),
                controlPoint1: CGPoint(x: CGFloat(size) * 0.68, y: CGFloat(size) * 0.81),
                controlPoint2: CGPoint(x: CGFloat(size) * 0.47, y: CGFloat(size) * 0.63))
    flare.close()
    flare.fill()

    let orbitColor = NSColor.white.withAlphaComponent(0.22)
    orbitColor.setStroke()
    let orbit = NSBezierPath()
    orbit.lineWidth = CGFloat(size) * 0.03
    orbit.move(to: CGPoint(x: CGFloat(size) * 0.20, y: CGFloat(size) * 0.34))
    orbit.curve(to: CGPoint(x: CGFloat(size) * 0.82, y: CGFloat(size) * 0.70),
                controlPoint1: CGPoint(x: CGFloat(size) * 0.36, y: CGFloat(size) * 0.14),
                controlPoint2: CGPoint(x: CGFloat(size) * 0.66, y: CGFloat(size) * 0.92))
    orbit.stroke()

    let ringOuter = NSBezierPath(ovalIn: NSRect(
        x: CGFloat(size) * 0.24,
        y: CGFloat(size) * 0.23,
        width: CGFloat(size) * 0.50,
        height: CGFloat(size) * 0.50
    ))
    NSColor.white.withAlphaComponent(0.95).setStroke()
    ringOuter.lineWidth = CGFloat(size) * 0.055
    ringOuter.stroke()

    let ringInner = NSBezierPath(ovalIn: NSRect(
        x: CGFloat(size) * 0.36,
        y: CGFloat(size) * 0.35,
        width: CGFloat(size) * 0.26,
        height: CGFloat(size) * 0.26
    ))
    NSColor(calibratedRed: 0.98, green: 0.63, blue: 0.28, alpha: 1).setFill()
    ringInner.fill()

    let crosshair = NSBezierPath()
    crosshair.lineWidth = CGFloat(size) * 0.028
    crosshair.lineCapStyle = .round
    crosshair.move(to: CGPoint(x: CGFloat(size) * 0.49, y: CGFloat(size) * 0.14))
    crosshair.line(to: CGPoint(x: CGFloat(size) * 0.49, y: CGFloat(size) * 0.27))
    crosshair.move(to: CGPoint(x: CGFloat(size) * 0.49, y: CGFloat(size) * 0.69))
    crosshair.line(to: CGPoint(x: CGFloat(size) * 0.49, y: CGFloat(size) * 0.82))
    crosshair.move(to: CGPoint(x: CGFloat(size) * 0.15, y: CGFloat(size) * 0.48))
    crosshair.line(to: CGPoint(x: CGFloat(size) * 0.28, y: CGFloat(size) * 0.48))
    crosshair.move(to: CGPoint(x: CGFloat(size) * 0.70, y: CGFloat(size) * 0.48))
    crosshair.line(to: CGPoint(x: CGFloat(size) * 0.83, y: CGFloat(size) * 0.48))
    NSColor.white.withAlphaComponent(0.92).setStroke()
    crosshair.stroke()

    let marker = NSBezierPath(roundedRect: NSRect(
        x: CGFloat(size) * 0.59,
        y: CGFloat(size) * 0.22,
        width: CGFloat(size) * 0.16,
        height: CGFloat(size) * 0.16
    ), xRadius: CGFloat(size) * 0.03, yRadius: CGFloat(size) * 0.03)
    NSColor(calibratedRed: 0.98, green: 0.63, blue: 0.28, alpha: 1).setFill()
    marker.fill()

    image.unlockFocus()
    return image
}

func resizedPNGData(from image: NSImage, size: Int) -> Data? {
    let bitmap = makeBitmap(size: size) {
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    }
    return bitmap.representation(using: .png, properties: [:])
}

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let baseImage = drawBaseIcon(size: 1024)

for (fileName, pixelSize) in iconSizes {
    guard let pngData = resizedPNGData(from: baseImage, size: pixelSize) else {
        fatalError("Unable to encode \(fileName)")
    }
    let outputURL = outputDirectory.appendingPathComponent(fileName)
    try pngData.write(to: outputURL)
    print("Wrote \(outputURL.path)")
}
