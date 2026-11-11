#!/usr/bin/env swift
import AppKit

// Draws the IAPGate app icon programmatically (no external SVG
// rasteriser needed) and emits an .iconset directory, which the
// accompanying shell script converts to Icon.icns with iconutil.
//
// Design: a rounded blue tile with a white shield and a keyhole,
// evoking "gated/authorised access".

func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = size

    // Background rounded tile with a vertical blue gradient.
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let corner = s * 0.22
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    ctx.addPath(bgPath)
    ctx.clip()
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let grad = CGGradient(colorsSpace: colorSpace, colors: [
        CGColor(red: 0.18, green: 0.42, blue: 0.90, alpha: 1),
        CGColor(red: 0.11, green: 0.23, blue: 0.55, alpha: 1)
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

    // Shield (white). Coordinates as fractions of the canvas.
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        // y flipped so the design reads top-down.
        CGPoint(x: x * s, y: (1 - y) * s)
    }
    let shield = CGMutablePath()
    shield.move(to: p(0.50, 0.19))
    shield.addLine(to: p(0.74, 0.29))
    shield.addLine(to: p(0.74, 0.51))
    shield.addCurve(to: p(0.50, 0.82), control1: p(0.74, 0.66), control2: p(0.63, 0.77))
    shield.addCurve(to: p(0.26, 0.51), control1: p(0.37, 0.77), control2: p(0.26, 0.66))
    shield.addLine(to: p(0.26, 0.29))
    shield.closeSubpath()
    ctx.addPath(shield)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()

    // Keyhole (blue): circle + stem.
    ctx.setFillColor(CGColor(red: 0.18, green: 0.42, blue: 0.90, alpha: 1))
    let r = s * 0.075
    let cx = 0.50 * s
    let cy = (1 - 0.46) * s
    ctx.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    let stem = CGRect(x: cx - s * 0.028, y: (1 - 0.61) * s, width: s * 0.056, height: s * 0.15)
    ctx.addPath(CGPath(roundedRect: stem, cornerWidth: s * 0.02, cornerHeight: s * 0.02, transform: nil))
    ctx.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Sizes required by iconutil (1x and 2x).
let specs: [(name: String, px: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
for spec in specs {
    let rep = drawIcon(size: spec.px)
    guard let data = rep.representation(using: .png, properties: [:]) else { continue }
    let url = URL(fileURLWithPath: "\(outDir)/\(spec.name).png")
    try? data.write(to: url)
}
print("Wrote iconset to \(outDir)")
