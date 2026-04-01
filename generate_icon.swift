#!/usr/bin/env swift
import AppKit

// Draws the HyperCaps icon: a stylised Caps Lock key cap on a gradient background.
// CG coordinate origin: bottom-left.
func drawIcon(ctx: CGContext, s: CGFloat) {
    let cs = CGColorSpaceCreateDeviceRGB()

    // ── 1. Background: dark gradient rounded rect ────────────────────────────
    let bgRadius = s * 0.22
    let bgPath = CGPath(roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: bgRadius, cornerHeight: bgRadius, transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let bgGrad = CGGradient(
        colorsSpace: cs,
        colors: [CGColor(red: 0.05, green: 0.32, blue: 0.58, alpha: 1),   // lighter at top
                 CGColor(red: 0.00, green: 0.25, blue: 0.50, alpha: 1)] as CFArray, // #004080 at bottom
        locations: [0, 1])!
    ctx.drawLinearGradient(bgGrad,
                           start: CGPoint(x: s / 2, y: s),
                           end:   CGPoint(x: s / 2, y: 0),
                           options: [])
    ctx.restoreGState()

    // ── 2. Key cap: rounded rectangle with subtle 3D effect ──────────────────
    let keyPad  = s * 0.15
    let keyX    = keyPad
    let keyY    = keyPad * 0.85
    let keyW    = s - keyPad * 2
    let keyH    = s - keyPad * 1.7
    let keyR    = s * 0.10

    // Key shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.025),
                  blur: s * 0.06,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.5))

    // Key face gradient (lighter top, darker bottom — gives 3D key look)
    let keyPath = CGPath(roundedRect: CGRect(x: keyX, y: keyY, width: keyW, height: keyH),
                         cornerWidth: keyR, cornerHeight: keyR, transform: nil)
    ctx.addPath(keyPath)
    ctx.clip()
    let keyGrad = CGGradient(
        colorsSpace: cs,
        colors: [CGColor(red: 0.92, green: 0.93, blue: 0.95, alpha: 1),   // top: light
                 CGColor(red: 0.72, green: 0.73, blue: 0.76, alpha: 1)] as CFArray, // bottom: medium grey
        locations: [0, 1])!
    ctx.drawLinearGradient(keyGrad,
                           start: CGPoint(x: s / 2, y: keyY + keyH),
                           end:   CGPoint(x: s / 2, y: keyY),
                           options: [])
    ctx.restoreGState()

    // Key border (subtle dark outline)
    ctx.setStrokeColor(CGColor(red: 0.35, green: 0.35, blue: 0.40, alpha: 0.6))
    ctx.setLineWidth(s * 0.008)
    ctx.addPath(keyPath)
    ctx.strokePath()

    // ── 3. Caps Lock arrow (⇪) — thick upward arrow ─────────────────────────
    let arrowColor = CGColor(red: 0.20, green: 0.20, blue: 0.25, alpha: 1)
    ctx.setFillColor(arrowColor)

    let centerX = s / 2
    let centerY = keyY + keyH / 2

    // Arrow dimensions relative to key size
    let arrowW   = keyW * 0.62       // total width of arrowhead
    let arrowH   = keyH * 0.34       // height of arrowhead triangle
    let stemW    = keyW * 0.26       // width of the stem
    let stemH    = keyH * 0.22       // height of the stem
    let arrowTop = centerY + keyH * 0.40   // top of arrowhead
    let arrowMid = arrowTop - arrowH       // bottom of arrowhead / top of stem
    let stemBot  = arrowMid - stemH        // bottom of stem

    // Draw as a single path: triangle on top, rectangle below
    ctx.beginPath()
    // Arrowhead triangle
    ctx.move(to: CGPoint(x: centerX, y: arrowTop))                         // tip
    ctx.addLine(to: CGPoint(x: centerX - arrowW / 2, y: arrowMid))        // bottom-left
    ctx.addLine(to: CGPoint(x: centerX - stemW / 2, y: arrowMid))         // inner-left
    // Stem
    ctx.addLine(to: CGPoint(x: centerX - stemW / 2, y: stemBot))          // stem bottom-left
    ctx.addLine(to: CGPoint(x: centerX + stemW / 2, y: stemBot))          // stem bottom-right
    ctx.addLine(to: CGPoint(x: centerX + stemW / 2, y: arrowMid))         // inner-right
    // Back to arrowhead
    ctx.addLine(to: CGPoint(x: centerX + arrowW / 2, y: arrowMid))        // bottom-right
    ctx.closePath()
    ctx.fillPath()

    // Underline bar below the stem (the ⇪ baseline)
    let barH = s * 0.04
    let barY = stemBot - barH - s * 0.018
    let barRect = CGRect(x: centerX - stemW / 2, y: barY, width: stemW, height: barH)
    let barPath = CGPath(roundedRect: barRect,
                         cornerWidth: barH / 2, cornerHeight: barH / 2, transform: nil)
    ctx.addPath(barPath)
    ctx.fillPath()

    // ── 4. Modifier badge dots (bottom-right, representing ⌘⌃⌥⇧) ────────────
    let badgeR   = s * 0.046
    let badgeGap = s * 0.028
    let totalW   = 4 * badgeR * 2 + 3 * badgeGap
    let badgeY   = keyY + keyH * 0.12
    let badgeStartX = centerX - totalW / 2 + badgeR

    let badgeColors: [CGColor] = [
        CGColor(red: 0.30, green: 0.65, blue: 1.00, alpha: 1),   // ⌃ blue
        CGColor(red: 0.40, green: 0.80, blue: 0.45, alpha: 1),   // ⌥ green
        CGColor(red: 0.95, green: 0.60, blue: 0.20, alpha: 1),   // ⇧ orange
        CGColor(red: 0.85, green: 0.30, blue: 0.35, alpha: 1),   // ⌘ red
    ]

    for i in 0 ..< 4 {
        let cx = badgeStartX + CGFloat(i) * (badgeR * 2 + badgeGap)
        ctx.setFillColor(badgeColors[i])
        ctx.addEllipse(in: CGRect(x: cx - badgeR, y: badgeY - badgeR,
                                   width: badgeR * 2, height: badgeR * 2))
        ctx.fillPath()
    }
}

// ── Render at given pixel size ───────────────────────────────────────────────
func renderIcon(pixels: Int) -> Data? {
    guard let bmp = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: NSColorSpaceName.deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    else { return nil }

    guard let ctx = NSGraphicsContext(bitmapImageRep: bmp)?.cgContext else { return nil }
    drawIcon(ctx: ctx, s: CGFloat(pixels))
    return bmp.representation(using: NSBitmapImageRep.FileType.png, properties: [:])
}

// ── Main ─────────────────────────────────────────────────────────────────────
let destDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

let sizes: [(String, Int)] = [
    ("icon_16x16.png",      16),
    ("icon_16x16@2x.png",   32),
    ("icon_32x32.png",      32),
    ("icon_32x32@2x.png",   64),
    ("icon_128x128.png",   128),
    ("icon_128x128@2x.png",256),
    ("icon_256x256.png",   256),
    ("icon_256x256@2x.png",512),
    ("icon_512x512.png",   512),
    ("icon_512x512@2x.png",1024),
]

for (filename, pixels) in sizes {
    if let data = renderIcon(pixels: pixels) {
        let url = URL(fileURLWithPath: destDir).appendingPathComponent(filename)
        try! data.write(to: url)
        print("✓  \(filename)  (\(pixels)px)")
    } else {
        print("✗  Failed: \(filename)")
    }
}
print("Done.")
