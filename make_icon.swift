#!/usr/bin/swift
// Generates AppIcon.iconset PNG files at all required macOS sizes.
// Design: deep indigo gradient background → white rounded-rect screen →
//         red REC dot → "GIF" badge in the bottom-right corner.

import AppKit
import CoreGraphics

let sizes: [(Int, Int)] = [
    (16, 1), (16, 2),
    (32, 1), (32, 2),
    (64, 1), (64, 2),
    (128, 1), (128, 2),
    (256, 1), (256, 2),
    (512, 1), (512, 2),
]

let iconsetDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(
    at: URL(fileURLWithPath: iconsetDir),
    withIntermediateDirectories: true
)

for (pts, scale) in sizes {
    let px = pts * scale
    let size = CGFloat(px)

    // --- draw into a CGContext ---
    let cs  = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)

    let bounds = NSRect(x: 0, y: 0, width: size, height: size)

    // ── Background: rounded rect with indigo→violet gradient ──
    let pad   = size * 0.0          // icon already fills square; macOS clips it
    let bgR   = NSRect(x: pad, y: pad,
                       width: size - pad * 2, height: size - pad * 2)
    let cornerR = size * 0.22
    let bgPath  = NSBezierPath(roundedRect: bgR, xRadius: cornerR, yRadius: cornerR)
    bgPath.addClip()

    // gradient: #1A1040 → #5B2D8E
    let g = NSGradient(
        colors: [
            NSColor(red: 0.08, green: 0.04, blue: 0.22, alpha: 1),
            NSColor(red: 0.36, green: 0.18, blue: 0.56, alpha: 1),
        ],
        atLocations: [0, 1],
        colorSpace: .sRGB
    )!
    g.draw(in: bgPath, angle: -45)

    // ── Screen shape (white rounded rect) ──
    let sInset  = size * 0.14
    let sBottom = size * 0.26
    let screenRect = NSRect(
        x: sInset,
        y: sBottom,
        width: size - sInset * 2,
        height: size - sInset - sBottom
    )
    let sCorner = size * 0.065
    let screenPath = NSBezierPath(roundedRect: screenRect, xRadius: sCorner, yRadius: sCorner)
    // white fill with slight transparency
    NSColor(white: 1, alpha: 0.92).setFill()
    screenPath.fill()

    // Screen inner: subtle dark inset (the "display content")
    let dispInset = size * 0.035
    let dispRect  = screenRect.insetBy(dx: dispInset, dy: dispInset)
    let dispPath  = NSBezierPath(roundedRect: dispRect, xRadius: sCorner * 0.6, yRadius: sCorner * 0.6)
    NSColor(red: 0.08, green: 0.04, blue: 0.22, alpha: 0.9).setFill()
    dispPath.fill()

    // Horizontal "scan lines" tint – three pale stripes representing frame content
    let stripeH = dispRect.height * 0.10
    let stripeGap = dispRect.height * 0.05
    var sy = dispRect.minY + dispRect.height * 0.18
    for _ in 0..<3 {
        let sr = NSRect(x: dispRect.minX + dispRect.width * 0.08, y: sy,
                        width: dispRect.width * 0.84, height: stripeH)
        NSBezierPath(roundedRect: sr, xRadius: stripeH/2, yRadius: stripeH/2)
            .fill()
        NSColor(white: 1, alpha: 0.08).setFill()
        // draw again as accent
        let srA = NSRect(x: dispRect.minX + dispRect.width * 0.08, y: sy,
                         width: dispRect.width * 0.35, height: stripeH)
        NSColor(red: 0.55, green: 0.30, blue: 0.90, alpha: 0.55).setFill()
        NSBezierPath(roundedRect: srA, xRadius: stripeH/2, yRadius: stripeH/2).fill()
        sy += stripeH + stripeGap
    }

    // ── Stand / base ──
    let baseW  = size * 0.28
    let baseH  = size * 0.055
    let neckH  = size * 0.055
    let baseX  = (size - baseW) / 2
    let baseY  = size * 0.10
    // neck
    let neckW  = size * 0.10
    let neckRect = NSRect(x: (size - neckW)/2, y: baseY + baseH - 1,
                          width: neckW, height: neckH + 1)
    NSColor(white: 0.85, alpha: 1).setFill()
    NSBezierPath(rect: neckRect).fill()
    // base
    let baseRect = NSRect(x: baseX, y: baseY, width: baseW, height: baseH)
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: baseH/2, yRadius: baseH/2)
    NSColor(white: 0.85, alpha: 1).setFill()
    basePath.fill()

    // ── REC dot (top-left inside display) ──
    if size >= 32 {
        let dotR   = size * 0.055
        let dotCX  = dispRect.minX + dispRect.width * 0.14
        let dotCY  = dispRect.maxY - dispRect.height * 0.17
        let dotRect = NSRect(x: dotCX - dotR, y: dotCY - dotR,
                             width: dotR * 2, height: dotR * 2)
        // glow
        NSColor(red: 1, green: 0.1, blue: 0.1, alpha: 0.30).setFill()
        NSBezierPath(ovalIn: dotRect.insetBy(dx: -dotR * 0.5, dy: -dotR * 0.5)).fill()
        // dot
        NSColor(red: 0.95, green: 0.15, blue: 0.15, alpha: 1).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
    }

    // ── "GIF" badge (bottom-right corner) ──
    if size >= 64 {
        let badgeSize = size * 0.36
        let badgeX    = size - badgeSize - size * 0.04
        let badgeY    = size * 0.04
        let badgeRect = NSRect(x: badgeX, y: badgeY,
                               width: badgeSize, height: badgeSize * 0.52)
        let badgePath = NSBezierPath(roundedRect: badgeRect,
                                     xRadius: badgeSize * 0.14,
                                     yRadius: badgeSize * 0.14)
        // badge fill
        NSColor(red: 0.95, green: 0.15, blue: 0.15, alpha: 1).setFill()
        badgePath.fill()

        // "GIF" text
        let fontSize  = badgeSize * 0.42
        let attrs: [NSAttributedString.Key: Any] = [
            .font:            NSFont.systemFont(ofSize: fontSize, weight: .black),
            .foregroundColor: NSColor.white,
        ]
        let str  = NSAttributedString(string: "GIF", attributes: attrs)
        let tSz  = str.size()
        let tX   = badgeRect.midX - tSz.width / 2
        let tY   = badgeRect.midY - tSz.height / 2
        str.draw(at: NSPoint(x: tX, y: tY))
    }

    NSGraphicsContext.restoreGraphicsState()

    // Write PNG
    guard let cgImage = ctx.makeImage() else { continue }
    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else { continue }

    let filename: String
    if scale == 1 {
        filename = "icon_\(pts)x\(pts).png"
    } else {
        filename = "icon_\(pts)x\(pts)@2x.png"
    }
    let url = URL(fileURLWithPath: "\(iconsetDir)/\(filename)")
    try! pngData.write(to: url)
    print("✓ \(filename)")
}

print("Done — run: iconutil -c icns AppIcon.iconset")
