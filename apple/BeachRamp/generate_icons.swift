#!/usr/bin/env swift

import Foundation
import AppKit

// Beach-themed icon: teal wave on sand/cream background
func generateIcon(size: Int, filename: String) {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))

    image.lockFocus()

    // Sand/cream background
    NSColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1.0).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: s, height: s)).fill()

    // Ocean teal gradient bottom half
    let oceanDark = NSColor(red: 0.05, green: 0.58, blue: 0.53, alpha: 1.0)  // ocean-600
    let oceanLight = NSColor(red: 0.08, green: 0.72, blue: 0.65, alpha: 1.0) // ocean-500

    // Draw ocean area (bottom ~55%)
    let oceanPath = NSBezierPath()
    let waveY = s * 0.50
    oceanPath.move(to: NSPoint(x: 0, y: 0))
    oceanPath.line(to: NSPoint(x: s, y: 0))
    oceanPath.line(to: NSPoint(x: s, y: waveY))

    // Wave curve across the top of the ocean
    oceanPath.curve(to: NSPoint(x: s * 0.5, y: waveY + s * 0.08),
                    controlPoint1: NSPoint(x: s * 0.85, y: waveY + s * 0.15),
                    controlPoint2: NSPoint(x: s * 0.65, y: waveY - s * 0.05))
    oceanPath.curve(to: NSPoint(x: 0, y: waveY + s * 0.02),
                    controlPoint1: NSPoint(x: s * 0.35, y: waveY + s * 0.18),
                    controlPoint2: NSPoint(x: s * 0.15, y: waveY - s * 0.05))
    oceanPath.close()

    oceanDark.setFill()
    oceanPath.fill()

    // Second wave (lighter, slightly above)
    let wave2Path = NSBezierPath()
    let wave2Y = s * 0.55
    wave2Path.move(to: NSPoint(x: 0, y: 0))
    wave2Path.line(to: NSPoint(x: s, y: 0))
    wave2Path.line(to: NSPoint(x: s, y: wave2Y - s * 0.08))

    wave2Path.curve(to: NSPoint(x: s * 0.5, y: wave2Y - s * 0.02),
                    controlPoint1: NSPoint(x: s * 0.80, y: wave2Y + s * 0.06),
                    controlPoint2: NSPoint(x: s * 0.60, y: wave2Y - s * 0.10))
    wave2Path.curve(to: NSPoint(x: 0, y: wave2Y - s * 0.05),
                    controlPoint1: NSPoint(x: s * 0.40, y: wave2Y + s * 0.08),
                    controlPoint2: NSPoint(x: s * 0.20, y: wave2Y - s * 0.10))
    wave2Path.close()

    oceanLight.setFill()
    wave2Path.fill()

    // Small white wave crests
    let crestColor = NSColor(white: 1.0, alpha: 0.4)
    crestColor.setStroke()

    let crest = NSBezierPath()
    crest.lineWidth = s * 0.015
    crest.move(to: NSPoint(x: s * 0.15, y: s * 0.35))
    crest.curve(to: NSPoint(x: s * 0.45, y: s * 0.35),
                controlPoint1: NSPoint(x: s * 0.25, y: s * 0.40),
                controlPoint2: NSPoint(x: s * 0.35, y: s * 0.30))
    crest.stroke()

    let crest2 = NSBezierPath()
    crest2.lineWidth = s * 0.012
    crest2.move(to: NSPoint(x: s * 0.50, y: s * 0.25))
    crest2.curve(to: NSPoint(x: s * 0.80, y: s * 0.25),
                 controlPoint1: NSPoint(x: s * 0.60, y: s * 0.30),
                 controlPoint2: NSPoint(x: s * 0.70, y: s * 0.20))
    crest2.stroke()

    image.unlockFocus()

    // Save as PNG
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(filename)")
        return
    }

    let url = URL(fileURLWithPath: filename)
    try! png.write(to: url)
    print("Generated: \(filename) (\(size)x\(size))")
}

// --- Generate all required sizes ---

let basePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// iOS app icon (single 1024x1024, Xcode generates the rest)
generateIcon(size: 1024, filename: "\(basePath)/AppIcon-1024.png")

// watchOS icon sizes
generateIcon(size: 1024, filename: "\(basePath)/WatchIcon-1024.png")

// tvOS icon sizes (needs layers but single image works for basic)
generateIcon(size: 1280, filename: "\(basePath)/TVIcon-1280.png")
generateIcon(size: 400, filename: "\(basePath)/TVIcon-400.png")

print("\nDone! Icon files generated.")
print("To use: drag these into the appropriate Asset Catalog in Xcode.")
