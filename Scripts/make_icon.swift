#!/usr/bin/env swift
//
// Generates Resources/AppIcon.icns for Magic Wand.
// Draws a purple-blue gradient squircle with the wand.and.stars SF Symbol
// rendered in white, exports all required sizes, and runs iconutil.
//
// Run:  swift Scripts/make_icon.swift
//

import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// macOS icon sizes (1x + 2x variants)
let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

func renderIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    )!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // Squircle background (Apple-style continuous corner radius)
    let inset = size * 0.09
    let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let cornerRadius = rect.width * 0.225
    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Gradient fill: purple top-left -> blue bottom-right
    let colors = [
        CGColor(red: 0.46, green: 0.23, blue: 0.93, alpha: 1.0),  // #7649ED
        CGColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1.0),  // #3B82F6
    ] as CFArray
    let space = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end: CGPoint(x: rect.maxX, y: rect.minY),
        options: []
    )

    // Reset clip to draw symbol
    ctx.resetClip()

    // SF Symbol: wand.and.stars in white, centered, ~58% of icon size
    let symbolSize = size * 0.58
    let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold)
    if let baseSymbol = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        baseSymbol.isTemplate = true
        let tinted = NSImage(size: baseSymbol.size, flipped: false) { r in
            baseSymbol.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }

        let sw = baseSymbol.size.width
        let sh = baseSymbol.size.height
        let drawRect = CGRect(
            x: (size - sw) / 2,
            y: (size - sh) / 2,
            width: sw,
            height: sh
        )
        // Soft shadow behind symbol
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -size * 0.01),
            blur: size * 0.03,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35)
        )
        tinted.draw(in: drawRect)
        ctx.restoreGState()
    }

    NSGraphicsContext.restoreGraphicsState()

    return rep.representation(using: .png, properties: [:])!
}

print("Rendering \(sizes.count) sizes...")
for (name, px) in sizes {
    let data = renderIcon(pixels: px)
    let url = iconset.appendingPathComponent(name)
    try data.write(to: url)
    print("  \(name)  (\(px)x\(px))")
}

// Build .icns via iconutil
let icns = resources.appendingPathComponent("AppIcon.icns")
try? FileManager.default.removeItem(at: icns)

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try task.run()
task.waitUntilExit()

guard task.terminationStatus == 0 else {
    print("iconutil failed (exit \(task.terminationStatus))")
    exit(1)
}

// Clean up the .iconset folder (we only ship the .icns)
try? FileManager.default.removeItem(at: iconset)

print("\n✔ Wrote \(icns.path)")
