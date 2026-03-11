#!/usr/bin/env swift

import Foundation
import AppKit

// Beach-themed tvOS icon: teal wave on sand/cream background (landscape)
func generateTVIcon(width: Int, height: Int, filename: String) {
    let w = CGFloat(width)
    let h = CGFloat(height)

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!

    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    // Sand/cream background
    NSColor(red: 0.99, green: 0.98, blue: 0.95, alpha: 1.0).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: w, height: h)).fill()

    // Ocean teal (bottom ~55%)
    let oceanDark = NSColor(red: 0.05, green: 0.58, blue: 0.53, alpha: 1.0)
    let oceanLight = NSColor(red: 0.08, green: 0.72, blue: 0.65, alpha: 1.0)

    let oceanPath = NSBezierPath()
    let waveY = h * 0.50
    oceanPath.move(to: NSPoint(x: 0, y: 0))
    oceanPath.line(to: NSPoint(x: w, y: 0))
    oceanPath.line(to: NSPoint(x: w, y: waveY))

    // Wave curve
    oceanPath.curve(to: NSPoint(x: w * 0.5, y: waveY + h * 0.08),
                    controlPoint1: NSPoint(x: w * 0.85, y: waveY + h * 0.15),
                    controlPoint2: NSPoint(x: w * 0.65, y: waveY - h * 0.05))
    oceanPath.curve(to: NSPoint(x: 0, y: waveY + h * 0.02),
                    controlPoint1: NSPoint(x: w * 0.35, y: waveY + h * 0.18),
                    controlPoint2: NSPoint(x: w * 0.15, y: waveY - h * 0.05))
    oceanPath.close()
    oceanDark.setFill()
    oceanPath.fill()

    // Second wave (lighter)
    let wave2Path = NSBezierPath()
    let wave2Y = h * 0.55
    wave2Path.move(to: NSPoint(x: 0, y: 0))
    wave2Path.line(to: NSPoint(x: w, y: 0))
    wave2Path.line(to: NSPoint(x: w, y: wave2Y - h * 0.08))
    wave2Path.curve(to: NSPoint(x: w * 0.5, y: wave2Y - h * 0.02),
                    controlPoint1: NSPoint(x: w * 0.80, y: wave2Y + h * 0.06),
                    controlPoint2: NSPoint(x: w * 0.60, y: wave2Y - h * 0.10))
    wave2Path.curve(to: NSPoint(x: 0, y: wave2Y - h * 0.05),
                    controlPoint1: NSPoint(x: w * 0.40, y: wave2Y + h * 0.08),
                    controlPoint2: NSPoint(x: w * 0.20, y: wave2Y - h * 0.10))
    wave2Path.close()
    oceanLight.setFill()
    wave2Path.fill()

    // White wave crests
    let crestColor = NSColor(white: 1.0, alpha: 0.4)
    crestColor.setStroke()

    let crest = NSBezierPath()
    crest.lineWidth = min(w, h) * 0.015
    crest.move(to: NSPoint(x: w * 0.10, y: h * 0.35))
    crest.curve(to: NSPoint(x: w * 0.35, y: h * 0.35),
                controlPoint1: NSPoint(x: w * 0.18, y: h * 0.40),
                controlPoint2: NSPoint(x: w * 0.27, y: h * 0.30))
    crest.stroke()

    let crest2 = NSBezierPath()
    crest2.lineWidth = min(w, h) * 0.012
    crest2.move(to: NSPoint(x: w * 0.45, y: h * 0.25))
    crest2.curve(to: NSPoint(x: w * 0.70, y: h * 0.25),
                 controlPoint1: NSPoint(x: w * 0.53, y: h * 0.30),
                 controlPoint2: NSPoint(x: w * 0.63, y: h * 0.20))
    crest2.stroke()

    let crest3 = NSBezierPath()
    crest3.lineWidth = min(w, h) * 0.010
    crest3.move(to: NSPoint(x: w * 0.65, y: h * 0.15))
    crest3.curve(to: NSPoint(x: w * 0.90, y: h * 0.15),
                 controlPoint1: NSPoint(x: w * 0.73, y: h * 0.20),
                 controlPoint2: NSPoint(x: w * 0.83, y: h * 0.10))
    crest3.stroke()

    NSGraphicsContext.restoreGraphicsState()

    // Save as PNG
    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(filename)")
        return
    }

    let url = URL(fileURLWithPath: filename)
    try! png.write(to: url)
    print("Generated: \(filename) (\(width)x\(height))")
}

let basePath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

// tvOS Home Screen icon layers: 400x240 (1x), 800x480 (2x)
generateTVIcon(width: 400, height: 240, filename: "\(basePath)/tv-icon-400x240.png")
generateTVIcon(width: 800, height: 480, filename: "\(basePath)/tv-icon-800x480.png")

// tvOS App Store icon layer: 1280x768
generateTVIcon(width: 1280, height: 768, filename: "\(basePath)/tv-icon-1280x768.png")

print("\nDone! TV icon layers generated.")
